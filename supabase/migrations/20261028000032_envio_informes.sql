-- Envío de informes al profesorado (especificación §7.10, criterio confirmado por Mark).
--
-- Cada docente recibe por correo un enlace personal a la versión docente de su informe (mínimo de 5 y complementaria),
-- válido 7 días. Cada apertura y cada descarga del PDF quedan registradas. Solo administración prepara y envía, siempre
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
  dias    smallint not null default 7 check (dias between 1 and 30)
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
  docente_id    integer not null references public.persona_responsable (id) on delete cascade,
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

-- Destinatarios de una selección, calculados siempre en el servidor. En modo pruebas (o con correo de prueba), cada
-- correo va al correo de prueba de Niage, nunca al docente.
create or replace function privado.destinatarios(p_curso smallint, p_seleccion jsonb, p_correo_prueba text)
returns table (docente_id integer, nombre text, apellidos text, departamento text, correo text, destinatario text, aviso text)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_modo   text := (select modo from privado.configuracion_envio);
  v_prueba text := nullif(lower(btrim(coalesce(p_correo_prueba, ''))), '');
begin
  if v_prueba is not null and not privado.correo_niage(v_prueba) then
    raise exception 'El correo de prueba tiene que ser de Niage (@niage.es o @niage.eu)' using errcode = '22023';
  end if;
  if v_modo = 'pruebas' and v_prueba is null then
    raise exception 'Envío en modo de pruebas: indica un correo de Niage. No se envía nada al profesorado.' using errcode = '22023';
  end if;
  return query
  select pr.id, pr.nombre, pr.apellidos, dep.nombre, pr.correo,
         case when v_prueba is not null then v_prueba else lower(btrim(pr.correo)) end,
         case when not privado.tiene_informe(p_curso, pr.id) then 'sin_resultados'
              when v_prueba is null and coalesce(btrim(pr.correo), '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then 'sin_correo' end
  from privado.docentes_seleccion(p_curso, p_seleccion) s
  join public.persona_responsable pr on pr.id = s.docente_id
  left join public.departamento dep on dep.id = pr.departamento_id
  order by pr.apellidos, pr.nombre;
end $$;

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
    insert into privado.enlace_informe (envio_id, curso_id, docente_id, destinatario, prueba, token_hash, token, caduca)
      values (v_envio, v_curso, d.docente_id, d.destinatario, v_prueba, privado.huella(v_token), v_token,
              now() + make_interval(days => v_conf.dias));
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then
    raise exception 'Ningún docente de la selección tiene informe y correo' using errcode = '22023';
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
    'nombre', pr.nombre, 'apellidos', pr.apellidos, 'correo_docente', pr.correo, 'curso', cu.nombre,
    'modo', (select modo from privado.configuracion_envio))), '[]')
  from privado.enlace_informe e
  join public.persona_responsable pr on pr.id = e.docente_id
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
      'id', e.id::text, 'docente', pr.nombre || ' ' || pr.apellidos, 'destinatario', e.destinatario, 'prueba', e.prueba,
      'creado', v.creado, 'enviado', e.enviado, 'error', e.error, 'caduca', e.caduca, 'anulado', e.anulado,
      'pendiente', e.token is not null and e.enviado is null and e.error is null,
      'aperturas', (select count(*) from privado.apertura_enlace a where a.enlace_id = e.id and a.tipo = 'apertura'),
      'descargas', (select count(*) from privado.apertura_enlace a where a.enlace_id = e.id and a.tipo = 'descarga'),
      'ultima', (select max(a.fecha) from privado.apertura_enlace a where a.enlace_id = e.id))
      order by v.creado desc, pr.apellidos, pr.nombre)
    from privado.enlace_informe e
    join privado.envio v on v.id = e.envio_id
    join public.persona_responsable pr on pr.id = e.docente_id
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
  update privado.enlace_informe set anulado = now(), token = null where id = p_enlace and anulado is null returning docente_id into v_doc;
  if v_doc is null then raise exception 'Enlace no encontrado' using errcode = 'P0002'; end if;
  perform privado.registrar('anular_enlace', jsonb_build_object('enlace', p_enlace::text, 'docente', v_doc));
end $$;

-- Enlace válido (no anulado ni caducado) a partir del token, o null.
create or replace function privado.enlace_valido(p_token text) returns privado.enlace_informe
language sql stable security definer set search_path = '' as $$
  select e.* from privado.enlace_informe e
  where e.token_hash = privado.huella(p_token) and e.anulado is null and length(coalesce(p_token, '')) >= 40;
$$;

-- Lo que abre el docente con su enlace, sin cuenta: la versión docente de su informe. Cada apertura queda registrada.
create or replace function public.informe_enlace(p_token text)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_e       privado.enlace_informe := privado.enlace_valido(p_token);
  v_doc     public.persona_responsable;
  v_dep     text;
  v_informe jsonb;
begin
  if v_e.id is null then
    raise exception 'Enlace no válido' using errcode = 'P0002';
  end if;
  if v_e.caduca < now() then
    return jsonb_build_object('estado', 'caducado', 'caduca', v_e.caduca);
  end if;
  select * into v_doc from public.persona_responsable where id = v_e.docente_id;
  select d.nombre into v_dep from public.departamento d where d.id = v_doc.departamento_id;
  insert into privado.apertura_enlace (enlace_id, tipo) values (v_e.id, 'apertura');
  insert into public.registro_actividad (usuario_id, accion, detalle)
    values (null, 'apertura_enlace', jsonb_build_object('enlace', v_e.id::text, 'docente', v_doc.id,
            'nombre', v_doc.nombre || ' ' || v_doc.apellidos, 'prueba', v_e.prueba));
  -- Siempre la versión docente: sin sesión no hay criterio de Dirección, y además se fuerza.
  perform set_config('encuestas.version_docente', 'on', true);
  v_informe := privado.informe_profesor(v_e.curso_id, v_e.docente_id, null);
  return jsonb_build_object('estado', 'ok', 'caduca', v_e.caduca,
    'curso', (select nombre from public.curso where id = v_e.curso_id),
    'profesor', jsonb_build_object('nombre', v_doc.nombre, 'apellidos', v_doc.apellidos, 'departamento', v_dep),
    'informe', v_informe);
end $$;

-- Descarga del PDF desde el enlace: queda en el registro de descargas con su código, a nombre del docente.
create or replace function public.descarga_enlace(p_token text, p_archivo text)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_e      privado.enlace_informe := privado.enlace_valido(p_token);
  v_doc    public.persona_responsable;
  v_nombre text;
  v_codigo text;
  v_fecha  timestamptz := now();
begin
  if v_e.id is null or v_e.caduca < now() then
    raise exception 'Enlace no válido o caducado' using errcode = 'P0002';
  end if;
  select * into v_doc from public.persona_responsable where id = v_e.docente_id;
  v_nombre := v_doc.nombre || ' ' || v_doc.apellidos;
  v_codigo := privado.codigo_descarga_libre('{}');
  insert into privado.apertura_enlace (enlace_id, tipo, codigo) values (v_e.id, 'descarga', v_codigo);
  insert into public.registro_actividad (usuario_id, accion, detalle, fecha)
    values (null, 'descarga', jsonb_build_object('codigo', v_codigo, 'tipo', 'informe_profesor',
            'curso', (select nombre from public.curso where id = v_e.curso_id), 'objeto', v_nombre, 'docente', v_doc.id,
            'archivo', left(coalesce(p_archivo, ''), 200), 'version', 'docente', 'enlace', v_e.id::text, 'nombre', v_nombre), v_fecha);
  return jsonb_build_object('codigo', v_codigo, 'nombre', v_nombre, 'fecha', v_fecha, 'informes', '[]'::jsonb);
end $$;

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
