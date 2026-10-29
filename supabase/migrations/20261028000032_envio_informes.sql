-- Envío de informes al profesorado (especificación §7.10, criterio confirmado por Mark).
--
-- Cada docente recibe por correo un enlace personal a la versión docente de su informe (mínimo de 5 y complementaria),
-- válido 7 días. Las jefaturas (de departamento y del Equipo de Individuación), igual, siempre con la versión para la
-- jefatura (decisión del 28/10/2026). Cada apertura y cada descarga del PDF quedan registradas. Solo administración prepara y envía, siempre
-- con vista previa de destinatarios. El correo lo manda la Edge Function enviar-informes.
--
-- Mientras no exista el remitente encuestas@sfpaula.com, el envío está en modo «pruebas»: solo a correos de Niage
-- (@niage.es o @niage.eu) y nunca al profesorado. Pasar a «activo» es un cambio en la base de datos que hace Niage
-- (privado.configuracion_envio), no un botón de la aplicación, y la Edge Function lo comprueba otra vez.
--
-- El token del enlace solo existe en claro hasta que sale el correo: después solo queda su huella (SHA-256).

create table privado.configuracion_envio (
  id      boolean primary key default true check (id),
  modo    text not null default 'pruebas' check (modo in ('pruebas', 'activo')),
  dias    smallint not null default 7 check (dias between 1 and 30),
  -- Límite de intentos fallidos con el enlace (tokens que no existen o anulados), en todo el servidor y por minuto.
  intentos_por_minuto smallint not null default 20 check (intentos_por_minuto between 1 and 1000)
);
insert into privado.configuracion_envio default values;

create table privado.envio (
  id           bigint primary key default privado.id_aleatorio(),
  curso_id     smallint not null references public.curso (id) on delete cascade,
  creado       timestamptz not null default now(),
  creado_por   uuid references auth.users (id) on delete set null,
  seleccion    jsonb not null,
  prueba       boolean not null
);

create table privado.enlace_informe (
  id            bigint primary key default privado.id_aleatorio(),
  envio_id      bigint not null references privado.envio (id) on delete cascade,
  curso_id      smallint not null references public.curso (id) on delete cascade,
  persona_id    integer not null references public.persona_responsable (id) on delete cascade,
  -- profesor: informe del profesor/a (versión docente); jefatura_departamento o jefatura_equipo (versión para la jefatura)
  tipo          text not null default 'profesor' check (tipo in ('profesor', 'jefatura_departamento', 'jefatura_equipo')),
  tramo         text check (tramo in ('infantil', 'y1_y5', 'y6_y9', 'y10_y12')),
  destinatario  text not null,
  prueba        boolean not null,
  token_hash    text not null unique,
  token         text,               -- en claro solo hasta que sale el correo
  caduca        timestamptz not null,
  enviado       timestamptz,
  error         text,
  anulado       timestamptz
);

create table privado.apertura_enlace (
  id         bigint primary key default privado.id_aleatorio(),
  enlace_id  bigint not null references privado.enlace_informe (id) on delete cascade,
  fecha      timestamptz not null default now(),
  tipo       text not null check (tipo in ('apertura', 'descarga')),
  codigo     text
);

create index on privado.apertura_enlace (enlace_id);

-- Intentos fallidos de abrir un enlace (token inventado, alterado o anulado). Sin IP ni token: solo la hora y el motivo.
-- Sirven para limitar los intentos al azar: pasado el límite por minuto, ningún enlace se abre durante ese minuto.
create table privado.intento_enlace (
  id      bigint generated always as identity primary key,
  fecha   timestamptz not null default now(),
  motivo  text not null
);

create index on privado.intento_enlace (fecha);

create or replace function privado.enlace_limitado() returns boolean
language sql stable security definer set search_path = '' as $$
  select count(*) >= (select intentos_por_minuto from privado.configuracion_envio)
  from privado.intento_enlace where fecha > now() - interval '1 minute';
$$;

create or replace function privado.fallo_enlace(p_motivo text) returns void
language sql volatile security definer set search_path = '' as $$
  delete from privado.intento_enlace where fecha < now() - interval '1 day';
  insert into privado.intento_enlace (motivo) values (p_motivo);
$$;

create or replace function privado.huella(p_token text) returns text
language sql immutable set search_path = '' as $$
  select encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
$$;

create or replace function privado.correo_niage(p_correo text) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(lower(btrim(p_correo)) ~ '^[a-z0-9._%+-]+@niage\.(es|eu)$', false);
$$;

-- Docentes de una selección: {"tipo": "docente"|"departamento"|"etapa"|"tramo"|"todos", "valores": [...]}.
-- Tramos: y1_y5, y6_y9, y10_y12 (por el curso de los grupos en los que da clase).
create or replace function privado.docentes_seleccion(p_curso smallint, p_sel jsonb)
returns table (docente_id integer)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_tipo    text := p_sel ->> 'tipo';
  v_valores text[] := array(select jsonb_array_elements_text(coalesce(p_sel -> 'valores', '[]')));
begin
  if v_tipo = 'jefaturas' then
    return;
  end if;
  if v_tipo is null or v_tipo not in ('docente', 'departamento', 'etapa', 'tramo', 'todos') then
    raise exception 'Selección no válida' using errcode = '22023';
  end if;
  if v_tipo <> 'todos' and cardinality(v_valores) = 0 then
    raise exception 'Elige al menos un valor' using errcode = '22023';
  end if;
  return query
  with docentes as (
    select distinct ad.docente_id, g.etapa, g.nivel
    from public.asignacion_docente ad join public.grupo g on g.id = ad.grupo_id
    where ad.curso_id = p_curso
    union
    select distinct rd.docente_id, c.etapa, g.nivel
    from privado.respuesta_docente rd join privado.respuesta r on r.id = rd.respuesta_id
    join public.cuestionario c on c.id = r.cuestionario_id left join public.grupo g on g.id = r.grupo_id
    where c.curso_id = p_curso
  )
  select distinct d.docente_id
  from docentes d
  join public.persona_responsable pr on pr.id = d.docente_id
  left join public.departamento dep on dep.id = pr.departamento_id
  where case v_tipo
    when 'todos' then true
    when 'docente' then d.docente_id::text = any(v_valores)
    when 'departamento' then dep.nombre = any(v_valores)
    when 'etapa' then d.etapa = any(v_valores)
    else (case when d.nivel ~ '^Y([1-5])$' then 'y1_y5' when d.nivel ~ '^Y([6-9])$' then 'y6_y9'
               when d.nivel ~ '^Y1[0-2]$' then 'y10_y12' end) = any(v_valores)
  end;
end $$;

-- ¿Tiene el docente algún resultado del alumnado en el curso? (Si no, no hay informe que enviar.)
create or replace function privado.tiene_informe(p_curso smallint, p_docente integer) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.asignacion_docente ad
    join public.grupo g on g.id = ad.grupo_id
    join privado.respuesta r on r.grupo_id = g.id
    join public.cuestionario c on c.id = r.cuestionario_id and c.colectivo = 'alumnos' and c.etapa = g.etapa
    where ad.curso_id = p_curso and ad.docente_id = p_docente)
  or exists (
    select 1 from privado.respuesta_docente rd join privado.respuesta r on r.id = rd.respuesta_id
    join public.cuestionario c on c.id = r.cuestionario_id
    where c.curso_id = p_curso and rd.docente_id = p_docente);
$$;

-- Destinatarios de una selección, calculados siempre en el servidor: una fila por informe (un docente, una jefatura de
-- departamento con todos sus departamentos, o una jefatura del Equipo de Individuación). Selección de jefaturas:
-- {"tipo": "jefaturas", "valores": [ids de persona]} (sin valores, todas). En modo pruebas (o con correo de prueba),
-- cada correo va al correo de prueba de Niage, nunca a la persona.
create or replace function privado.destinatarios(p_curso smallint, p_seleccion jsonb, p_correo_prueba text)
returns table (persona_id integer, tipo text, tramo text, informe text, nombre text, apellidos text, departamento text,
               correo text, destinatario text, aviso text)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_modo   text := (select modo from privado.configuracion_envio);
  v_prueba text := nullif(lower(btrim(coalesce(p_correo_prueba, ''))), '');
  v_ids    text[] := array(select jsonb_array_elements_text(coalesce(p_seleccion -> 'valores', '[]')));
begin
  if v_prueba is not null and not privado.correo_niage(v_prueba) then
    raise exception 'El correo de prueba tiene que ser de Niage (@niage.es o @niage.eu)' using errcode = '22023';
  end if;
  if v_modo = 'pruebas' and v_prueba is null then
    raise exception 'Envío en modo de pruebas: indica un correo de Niage. No se envía nada al profesorado.' using errcode = '22023';
  end if;
  return query
  with filas as (
    select s.docente_id as pid, 'profesor'::text as tipo, null::text as tramo, null::text as informe,
           not privado.tiene_informe(p_curso, s.docente_id) as sin_informe
    from privado.docentes_seleccion(p_curso, p_seleccion) s
    union all
    select ca.persona_id, 'jefatura_departamento', null, string_agg(ca.ambito, ', ' order by ca.ambito), false
    from public.cargo ca
    where p_seleccion ->> 'tipo' = 'jefaturas' and ca.curso_id = p_curso and ca.tipo = 'jefe_departamento'
      and (cardinality(v_ids) = 0 or ca.persona_id::text = any(v_ids))
    group by ca.persona_id
    union all
    select ca.persona_id, 'jefatura_equipo', ca.ambito, ca.ambito, false
    from public.cargo ca
    where p_seleccion ->> 'tipo' = 'jefaturas' and ca.curso_id = p_curso and ca.tipo = 'jefe_equipo'
      and (cardinality(v_ids) = 0 or ca.persona_id::text = any(v_ids))
  )
  select pr.id, f.tipo, f.tramo, f.informe, pr.nombre, pr.apellidos, dep.nombre, pr.correo,
         case when v_prueba is not null then v_prueba else lower(btrim(pr.correo)) end,
         case when f.sin_informe then 'sin_resultados'
              when v_prueba is null and coalesce(btrim(pr.correo), '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then 'sin_correo' end
  from filas f
  join public.persona_responsable pr on pr.id = f.pid
  left join public.departamento dep on dep.id = pr.departamento_id
  order by pr.apellidos, pr.nombre, f.tipo, f.tramo;
end $$;

-- Jefaturas del curso, para elegir a quién enviar (con sus cargos).
create or replace function public.admin_jefaturas(p_curso text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', pr.id, 'nombre', pr.nombre, 'apellidos', pr.apellidos,
             'departamentos', coalesce((select jsonb_agg(c.ambito order by c.ambito) from public.cargo c
                                        where c.persona_id = pr.id and c.curso_id = cu.id and c.tipo = 'jefe_departamento'), '[]'),
             'tramos', coalesce((select jsonb_agg(c.ambito order by c.ambito) from public.cargo c
                                 where c.persona_id = pr.id and c.curso_id = cu.id and c.tipo = 'jefe_equipo'), '[]'))
           order by pr.apellidos, pr.nombre)
    from public.persona_responsable pr, public.curso cu
    where cu.nombre = p_curso
      and exists (select 1 from public.cargo c where c.persona_id = pr.id and c.curso_id = cu.id and c.tipo in ('jefe_departamento', 'jefe_equipo'))
  ), '[]');
end $$;

revoke execute on function public.admin_jefaturas(text) from public, anon;
grant execute on function public.admin_jefaturas(text) to authenticated;

-- Vista previa: a quién se enviaría, a qué correo y quién se queda fuera (y por qué). No envía nada.
create or replace function public.admin_envio_destinatarios(p_curso text, p_seleccion jsonb, p_correo_prueba text default null)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_curso smallint := (select id from public.curso where nombre = p_curso);
begin
  perform privado.exigir_admin();
  if v_curso is null then raise exception 'Curso no encontrado' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'modo', (select modo from privado.configuracion_envio),
    'dias', (select dias from privado.configuracion_envio),
    'destinatarios', coalesce((select jsonb_agg(to_jsonb(d)) from privado.destinatarios(v_curso, p_seleccion, p_correo_prueba) d), '[]'));
end $$;

-- Crea los enlaces (uno por docente con informe y correo) y deja los correos listos para la Edge Function.
create or replace function public.admin_envio_crear(p_curso text, p_seleccion jsonb, p_correo_prueba text default null)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_perfil public.usuario_perfil := privado.exigir_admin();
  v_curso  smallint := (select id from public.curso where nombre = p_curso);
  v_conf   privado.configuracion_envio := (select c from privado.configuracion_envio c);
  v_prueba boolean := nullif(btrim(coalesce(p_correo_prueba, '')), '') is not null;
  v_envio  bigint;
  v_n      integer := 0;
  v_fuera  integer := 0;
  v_token  text;
  d        record;
begin
  if v_curso is null then raise exception 'Curso no encontrado' using errcode = 'P0002'; end if;
  insert into privado.envio (curso_id, creado_por, seleccion, prueba) values (v_curso, v_perfil.id, p_seleccion, v_prueba)
    returning id into v_envio;
  for d in select * from privado.destinatarios(v_curso, p_seleccion, p_correo_prueba) loop
    if d.aviso is not null then v_fuera := v_fuera + 1; continue; end if;
    if v_conf.modo = 'pruebas' and not privado.correo_niage(d.destinatario) then
      raise exception 'Modo de pruebas: solo correos de Niage' using errcode = '42501';
    end if;
    v_token := translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/=', '-_');
    insert into privado.enlace_informe (envio_id, curso_id, persona_id, tipo, tramo, destinatario, prueba, token_hash, token, caduca)
      values (v_envio, v_curso, d.persona_id, d.tipo, d.tramo, d.destinatario, v_prueba, privado.huella(v_token), v_token,
              now() + make_interval(days => v_conf.dias));
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then
    raise exception 'Nadie de la selección tiene informe y correo' using errcode = '22023';
  end if;
  perform privado.registrar('envio_informes', jsonb_build_object('curso', p_curso, 'envio', v_envio::text, 'seleccion', p_seleccion,
    'enlaces', v_n, 'fuera', v_fuera, 'prueba', v_prueba, 'correo_prueba', case when v_prueba then lower(btrim(p_correo_prueba)) end));
  return jsonb_build_object('envio', v_envio::text, 'enlaces', v_n, 'fuera', v_fuera, 'prueba', v_prueba);
end $$;

-- Para la Edge Function (clave de servicio): los correos pendientes de un envío, con su token, y marcar cada uno.
create or replace function public.envio_pendientes(p_envio bigint)
returns jsonb
language sql volatile security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'enlace', e.id::text, 'token', e.token, 'destinatario', e.destinatario, 'prueba', e.prueba, 'caduca', e.caduca,
    'tipo', e.tipo, 'tramo', e.tramo,
    'nombre', pr.nombre, 'apellidos', pr.apellidos, 'correo_docente', pr.correo, 'curso', cu.nombre,
    'modo', (select modo from privado.configuracion_envio))), '[]')
  from privado.enlace_informe e
  join public.persona_responsable pr on pr.id = e.persona_id
  join public.curso cu on cu.id = e.curso_id
  where e.envio_id = p_envio and e.enviado is null and e.error is null and e.token is not null and e.anulado is null;
$$;

create or replace function public.envio_marcar(p_enlace bigint, p_error text default null)
returns void
language sql volatile security definer set search_path = '' as $$
  update privado.enlace_informe
     set enviado = case when p_error is null then now() end, error = left(p_error, 500), token = null
   where id = p_enlace;
$$;

-- Enlaces enviados del curso, con sus aperturas y descargas (solo administración).
create or replace function public.admin_envios(p_curso text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', e.id::text, 'docente', pr.nombre || ' ' || pr.apellidos, 'tipo', e.tipo, 'tramo', e.tramo,
      'destinatario', e.destinatario, 'prueba', e.prueba,
      'creado', v.creado, 'enviado', e.enviado, 'error', e.error, 'caduca', e.caduca, 'anulado', e.anulado,
      'pendiente', e.token is not null and e.enviado is null and e.error is null,
      'aperturas', (select count(*) from privado.apertura_enlace a where a.enlace_id = e.id and a.tipo = 'apertura'),
      'descargas', (select count(*) from privado.apertura_enlace a where a.enlace_id = e.id and a.tipo = 'descarga'),
      'ultima', (select max(a.fecha) from privado.apertura_enlace a where a.enlace_id = e.id))
      order by v.creado desc, pr.apellidos, pr.nombre)
    from privado.enlace_informe e
    join privado.envio v on v.id = e.envio_id
    join public.persona_responsable pr on pr.id = e.persona_id
    join public.curso cu on cu.id = e.curso_id
    where cu.nombre = p_curso), '[]');
end $$;

create or replace function public.admin_enlace_anular(p_enlace bigint)
returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_doc integer;
begin
  perform privado.exigir_admin();
  update privado.enlace_informe set anulado = now(), token = null where id = p_enlace and anulado is null returning persona_id into v_doc;
  if v_doc is null then raise exception 'Enlace no encontrado' using errcode = 'P0002'; end if;
  perform privado.registrar('anular_enlace', jsonb_build_object('enlace', p_enlace::text, 'persona', v_doc));
end $$;

-- Enlace válido (no anulado ni caducado) a partir del token, o null.
create or replace function privado.enlace_valido(p_token text) returns privado.enlace_informe
language sql stable security definer set search_path = '' as $$
  select e.* from privado.enlace_informe e
  where e.token_hash = privado.huella(p_token) and e.anulado is null and length(coalesce(p_token, '')) >= 40;
$$;

-- Los informes de jefatura pasan por privado.resolver, que exige una sesión. Desde un enlace personal no la hay: tras
-- validar el token, informe_enlace marca la transacción (encuestas.enlace) y resolver la acepta sin perfil, con el mínimo
-- de 5 (sin perfil no hay criterio de Dirección). Ese ajuste es local a la transacción y solo lo pone informe_enlace.
create or replace function privado.exigir_o_enlace() returns public.usuario_perfil
language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(current_setting('encuestas.enlace', true), '') = 'on' and auth.uid() is null then
    return null::public.usuario_perfil;
  end if;
  return permisos.exigir();
end $$;

revoke execute on function privado.exigir_o_enlace() from public, anon, authenticated;

create or replace function privado.resolver(p_filtro jsonb, p_dims text[])
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_perfil     public.usuario_perfil := privado.exigir_o_enlace();
  v_filtro     jsonb := coalesce(p_filtro, '{}');
  v_col        text := v_filtro ->> 'colectivo';
  v_curso      smallint;
  v_cuest      integer[];
  v_particion  text[];
  v_fijos      jsonb := '{}';
  v_dims       text[] := '{}';
  v_salida     text[] := '{}';
  v_seg        integer;
  k            text;
begin
  if v_col is null or v_col not in ('alumnos', 'familias', 'personal') then
    raise exception 'Colectivo no válido: %', coalesce(v_col, '(vacío)');
  end if;

  select id into v_curso from public.curso where nombre = v_filtro ->> 'curso';
  if v_curso is null then
    raise exception 'Curso no encontrado: %', coalesce(v_filtro ->> 'curso', '(vacío)');
  end if;

  v_particion := case v_col
    when 'alumnos'  then array['cuestionario', 'etapa', 'grupo', 'asignatura', 'recomienda']
    when 'familias' then array['etapa', 'recomienda']
    else array['docente', 'antiguedad', 'departamento_equipo', 'departamento', 'tramo', 'recomienda']
  end;

  for k in select jsonb_object_keys(v_filtro) loop
    if k not in ('curso', 'colectivo', 'referencia') and not k = any(v_particion)
       and not (v_col = 'alumnos' and k = 'etapas') then
      raise exception 'Filtro no válido para %: %', v_col, k;
    end if;
  end loop;
  foreach k in array coalesce(p_dims, '{}') loop
    if not k = any(v_particion) then
      raise exception 'Dimensión no válida para %: %', v_col, k;
    end if;
  end loop;

  -- Referencia del colegio (decisión del 26/10/2026): la coordinación puede ver el resultado de las familias de
  -- todo el colegio, sin repartir ni filtrar, junto al de su etapa. Es un agregado del colegio entero.
  if v_filtro ? 'referencia' then
    if v_col <> 'familias' or (v_filtro ->> 'referencia') <> 'true' or cardinality(coalesce(p_dims, '{}')) > 0
       or exists (select 1 from jsonb_object_keys(v_filtro) x where x not in ('curso', 'colectivo', 'referencia')) then
      raise exception 'La referencia del Colegio es solo el total de familias, sin filtros ni repartos';
    end if;
    v_filtro := v_filtro - 'referencia';
  elsif v_perfil.rol = 'coordinacion' then
    if v_col = 'personal' then
      raise exception 'Sin acceso a los resultados de personal' using errcode = '42501';
    end if;
    if v_filtro ? 'etapa' and v_filtro ->> 'etapa' <> v_perfil.etapa then
      raise exception 'Sin acceso a la etapa %', v_filtro ->> 'etapa' using errcode = '42501';
    end if;
    v_filtro := v_filtro || jsonb_build_object('etapa', v_perfil.etapa);
  end if;

  select coalesce(array_agg(c.id order by c.id), '{}') into v_cuest
  from public.cuestionario c
  where c.curso_id = v_curso
    and c.colectivo = v_col
    and (v_col <> 'alumnos' or not v_filtro ? 'etapa' or c.etapa = v_filtro ->> 'etapa')
    and (v_col <> 'alumnos' or not v_filtro ? 'cuestionario' or c.codigo = v_filtro ->> 'cuestionario')
    and (v_col <> 'alumnos' or not v_filtro ? 'etapas'
         or c.etapa = any(array(select jsonb_array_elements_text(v_filtro -> 'etapas'))));
  if cardinality(v_cuest) = 0 then
    raise exception 'No hay datos para este filtro' using errcode = 'P0002';
  end if;

  foreach k in array v_particion loop
    continue when not v_filtro ? k;
    continue when v_col = 'alumnos' and k in ('cuestionario', 'etapa');
    v_fijos := v_fijos || jsonb_build_object(k, case
      when k = 'docente' and jsonb_typeof(v_filtro -> k) = 'boolean'
        then case when (v_filtro ->> k)::boolean then 'docente' else 'no_docente' end
      else v_filtro ->> k
    end);
  end loop;

  foreach k in array v_particion loop
    if v_fijos ? k or k = any(coalesce(p_dims, '{}')) then
      v_dims := v_dims || k;
      if not v_fijos ? k then
        v_salida := v_salida || k;
      end if;
    end if;
  end loop;

  -- La comparación por recomendación va sola: sin grupo, etapa, segmento ni ningún otro filtro.
  if 'recomienda' = any(v_dims) and cardinality(v_dims) > 1 then
    raise exception 'La comparación por recomendación no se combina con otros filtros';
  end if;

  if cardinality(v_dims) > 2 then
    raise exception 'Como máximo dos dimensiones a la vez';
  end if;

  if v_col = 'personal' then
    select count(*) into v_seg from unnest(v_dims) d
    where d in ('docente', 'antiguedad', 'departamento_equipo', 'tramo');
    if v_seg > 1 then
      raise exception 'Los filtros de personal no se combinan: usa uno a la vez';
    end if;
  end if;

  return jsonb_build_object(
    'curso_id', v_curso,
    'colectivo', v_col,
    'cuestionarios', to_jsonb(v_cuest),
    'dims', to_jsonb(v_dims),
    'fijos', v_fijos,
    'salida', to_jsonb(v_salida)
  );
end $$;



-- Lo que abre el docente o la jefatura con su enlace, sin cuenta: la versión docente o la versión para la jefatura de su
-- informe (mínimo de 5 y complementaria, siempre). Cada apertura queda registrada.
-- Sin excepciones en los fallos, para que el intento fallido quede anotado (una excepción lo desharía):
--   limitado:  demasiados intentos fallidos en el último minuto (no se mira el token);
--   no_valido: token inventado, alterado o de un enlace anulado (cuenta como intento fallido);
--   caducado:  el enlace existe pero han pasado sus días.
create or replace function public.informe_enlace(p_token text)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_e       privado.enlace_informe;
  v_pr      public.persona_responsable;
  v_dep     text;
  v_curso   text;
  v_informe jsonb;
begin
  if privado.enlace_limitado() then
    return jsonb_build_object('estado', 'limitado');
  end if;
  v_e := privado.enlace_valido(p_token);
  if v_e.id is null then
    perform privado.fallo_enlace('no_valido');
    return jsonb_build_object('estado', 'no_valido');
  end if;
  if v_e.caduca < now() then
    return jsonb_build_object('estado', 'caducado', 'caduca', v_e.caduca);
  end if;
  select * into v_pr from public.persona_responsable where id = v_e.persona_id;
  select d.nombre into v_dep from public.departamento d where d.id = v_pr.departamento_id;
  select nombre into v_curso from public.curso where id = v_e.curso_id;
  insert into privado.apertura_enlace (enlace_id, tipo) values (v_e.id, 'apertura');
  insert into public.registro_actividad (usuario_id, accion, detalle)
    values (null, 'apertura_enlace', jsonb_build_object('enlace', v_e.id::text, 'persona', v_pr.id, 'informe', v_e.tipo,
            'nombre', v_pr.nombre || ' ' || v_pr.apellidos, 'prueba', v_e.prueba));
  -- Siempre con el mínimo de 5: sin sesión no hay criterio de Dirección, y además se fuerza.
  perform set_config('encuestas.version_docente', 'on', true);
  perform set_config('encuestas.enlace', 'on', true);
  v_informe := case v_e.tipo
    when 'profesor' then privado.informe_profesor(v_e.curso_id, v_e.persona_id, null)
    when 'jefatura_departamento' then privado.informe_jefatura_departamento(v_curso, v_e.persona_id) || '{"version": "jefatura"}'
    else privado.informe_jefatura_equipo(v_curso, array[v_e.tramo], true) || '{"version": "jefatura"}' end;
  perform set_config('encuestas.enlace', '', true);
  return jsonb_build_object('estado', 'ok', 'caduca', v_e.caduca, 'curso', v_curso, 'tipo', v_e.tipo,
    'profesor', jsonb_build_object('nombre', v_pr.nombre, 'apellidos', v_pr.apellidos, 'departamento', v_dep),
    'informe', v_informe);
end $$;

-- Descarga del PDF desde el enlace: queda en el registro de descargas con su código, a nombre de la persona.
create or replace function public.descarga_enlace(p_token text, p_archivo text)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_e      privado.enlace_informe;
  v_pr     public.persona_responsable;
  v_nombre text;
  v_codigo text;
  v_fecha  timestamptz := now();
begin
  if privado.enlace_limitado() then
    return jsonb_build_object('estado', 'limitado');
  end if;
  v_e := privado.enlace_valido(p_token);
  if v_e.id is null then
    perform privado.fallo_enlace('no_valido');
    return jsonb_build_object('estado', 'no_valido');
  end if;
  if v_e.caduca < now() then
    return jsonb_build_object('estado', 'caducado');
  end if;
  select * into v_pr from public.persona_responsable where id = v_e.persona_id;
  v_nombre := v_pr.nombre || ' ' || v_pr.apellidos;
  v_codigo := privado.codigo_descarga_libre('{}');
  insert into privado.apertura_enlace (enlace_id, tipo, codigo) values (v_e.id, 'descarga', v_codigo);
  insert into public.registro_actividad (usuario_id, accion, detalle, fecha)
    values (null, 'descarga', jsonb_strip_nulls(jsonb_build_object('codigo', v_codigo,
            'tipo', case v_e.tipo when 'profesor' then 'informe_profesor' when 'jefatura_departamento' then 'informe_jefatura' else 'informe_equipo' end,
            'curso', (select nombre from public.curso where id = v_e.curso_id), 'objeto', v_nombre,
            'docente', case when v_e.tipo = 'profesor' then v_pr.id end, 'persona', case when v_e.tipo <> 'profesor' then v_pr.id end,
            'tramos', case when v_e.tramo is not null then jsonb_build_array(v_e.tramo) end,
            'archivo', left(coalesce(p_archivo, ''), 200), 'version', case when v_e.tipo = 'profesor' then 'docente' else 'jefatura' end,
            'enlace', v_e.id::text, 'nombre', v_nombre)), v_fecha);
  return jsonb_build_object('codigo', v_codigo, 'nombre', v_nombre, 'fecha', v_fecha, 'informes', '[]'::jsonb);
end $$;

revoke execute on function privado.enlace_limitado(), privado.fallo_enlace(text) from public, anon, authenticated;
revoke execute on function privado.huella(text), privado.correo_niage(text), privado.docentes_seleccion(smallint, jsonb),
  privado.tiene_informe(smallint, integer), privado.destinatarios(smallint, jsonb, text), privado.enlace_valido(text)
  from public, anon, authenticated;
revoke execute on function public.admin_envio_destinatarios(text, jsonb, text), public.admin_envio_crear(text, jsonb, text),
  public.admin_envios(text), public.admin_enlace_anular(bigint) from public, anon;
grant execute on function public.admin_envio_destinatarios(text, jsonb, text), public.admin_envio_crear(text, jsonb, text),
  public.admin_envios(text), public.admin_enlace_anular(bigint) to authenticated;
revoke execute on function public.envio_pendientes(bigint), public.envio_marcar(bigint, text) from public, anon, authenticated;
grant execute on function public.envio_pendientes(bigint), public.envio_marcar(bigint, text) to service_role;
revoke execute on function public.informe_enlace(text), public.descarga_enlace(text, text) from public;
grant execute on function public.informe_enlace(text), public.descarga_enlace(text, text) to anon, authenticated;
