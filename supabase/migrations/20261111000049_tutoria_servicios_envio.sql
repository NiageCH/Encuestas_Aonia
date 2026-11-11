-- Informes de tutoría y de servicios, y envío en un paso (petición de Mark del 11/11/2026, especificación §7.12 a §7.14).
--
-- Tutoría: un informe por grupo para su tutor/a (no para el cotutor/a), con las preguntas del alumnado sobre el tutor/a
-- en su grupo y, como referencia, la media de toda la etapa (todos los tutores) y, del Colegio, la labor tutorial según
-- las familias y el personal (solo como referencia: no traen grupo). Los tutores salen de la hoja «Tutores» de Alexia
-- (etl/cargar_tutores_2526.py).
--
-- Servicios: un informe por servicio para su responsable (sin copia al directivo), con la valoración de cada colectivo
-- (alumnado y familias por etapa; el personal solo valora la Biblioteca y el Servicio de Orientación). Qué preguntas son
-- de cada servicio lo carga etl/cargar_informes_2526.py; quién es responsable lo mantiene administración desde la
-- aplicación (admin_servicio_responsable).
--
-- Las dos versiones de siempre: la completa (Dirección y administración, con la marca «menos de 5») y la del destinatario
-- (mínimo de 5 y supresión complementaria). Todo sale de public.resultados, así que una celda del informe es la misma
-- que ve la coordinación en Alumnado o Familias con los mismos filtros, con la misma supresión conjunta.
--
-- Envío en un paso: se elige el tipo de informe y por defecto van todos sus destinatarios; la vista previa avisa de quién
-- se queda fuera (sin destinatario, sin correo, sin resultados), de quién no tendría ningún resultado visible en su
-- versión y de quién ya lo recibió, y se puede quitar a quien se quiera antes de enviar.

-- Tablas -------------------------------------------------------------------------------------------------------------

create table public.tutoria (
  curso_id    smallint not null references public.curso (id) on delete cascade,
  grupo_id    integer not null references public.grupo (id) on delete cascade,
  persona_id  integer not null references public.persona_responsable (id) on delete cascade,
  primary key (curso_id, grupo_id)
);

-- Preguntas del informe de tutoría: «grupo», las del alumnado sobre su tutor/a; «colegio», la labor tutorial según las
-- familias y el personal, solo como referencia del Colegio.
create table public.tutoria_pregunta (
  curso_id     smallint not null references public.curso (id) on delete cascade,
  pregunta_id  integer not null references public.pregunta (id) on delete cascade,
  ambito       text not null check (ambito in ('grupo', 'colegio')),
  orden        smallint not null default 0,
  primary key (curso_id, pregunta_id)
);

create table public.servicio (
  id        integer generated always as identity primary key,
  curso_id  smallint not null references public.curso (id) on delete cascade,
  codigo    text not null,
  nombre    text not null,
  orden     smallint not null default 0,
  unique (curso_id, codigo)
);

-- principal: la valoración del servicio en el bloque de servicios de cada encuesta; si no, preguntas propias del
-- servicio en otros bloques (por ejemplo, «En la Biblioteca me atienden bien»).
create table public.servicio_pregunta (
  servicio_id  integer not null references public.servicio (id) on delete cascade,
  pregunta_id  integer not null references public.pregunta (id) on delete cascade,
  principal    boolean not null default true,
  orden        smallint not null default 0,
  primary key (servicio_id, pregunta_id)
);

-- Un responsable por servicio y curso (el servicio ya es de un curso).
create table public.responsable_servicio (
  servicio_id      integer primary key references public.servicio (id) on delete cascade,
  persona_id       integer not null references public.persona_responsable (id) on delete cascade,
  actualizado      timestamptz not null default now(),
  actualizado_por  uuid references auth.users (id) on delete set null
);

alter table public.tutoria enable row level security;
alter table public.tutoria_pregunta enable row level security;
alter table public.servicio enable row level security;
alter table public.servicio_pregunta enable row level security;
alter table public.responsable_servicio enable row level security;
-- Como los cargos: solo Dirección y administración las leen, y nadie escribe desde el cliente (las altas de
-- responsables pasan por admin_servicio_responsable).
create policy lectura_direccion on public.tutoria for select to authenticated using (permisos.ve_todo());
create policy lectura_direccion on public.tutoria_pregunta for select to authenticated using (permisos.ve_todo());
create policy lectura_direccion on public.servicio for select to authenticated using (permisos.ve_todo());
create policy lectura_direccion on public.servicio_pregunta for select to authenticated using (permisos.ve_todo());
create policy lectura_direccion on public.responsable_servicio for select to authenticated using (permisos.ve_todo());
revoke insert, update, delete, truncate on public.tutoria, public.tutoria_pregunta, public.servicio, public.servicio_pregunta,
  public.responsable_servicio from anon, authenticated;
revoke all on public.tutoria, public.tutoria_pregunta, public.servicio, public.servicio_pregunta, public.responsable_servicio from anon;

-- Enlaces de los informes nuevos: el del tutor/a lleva su grupo y el del responsable, su servicio.
alter table privado.enlace_informe drop constraint enlace_informe_tipo_check;
alter table privado.enlace_informe add constraint enlace_informe_tipo_check
  check (tipo in ('profesor', 'jefatura_departamento', 'jefatura_equipo', 'tutoria', 'servicio'));
alter table privado.enlace_informe
  add column grupo_id integer references public.grupo (id) on delete cascade,
  add column servicio_id integer references public.servicio (id) on delete cascade;
alter table privado.enlace_informe add constraint enlace_informe_ambito_check check (
  (tipo = 'tutoria') = (grupo_id is not null) and (tipo = 'servicio') = (servicio_id is not null));

-- Versión del destinatario mientras se calcula un informe -------------------------------------------------------------

-- Pone o quita el ajuste que endurece el criterio (encuestas.version_docente) y devuelve el que había, para dejarlo igual.
create or replace function privado.version_destinatario(p_on boolean) returns text
language plpgsql volatile set search_path = '' as $$
declare
  v_previo text := coalesce(current_setting('encuestas.version_docente', true), '');
begin
  if p_on then perform set_config('encuestas.version_docente', 'on', true); end if;
  return v_previo;
end $$;

revoke execute on function privado.version_destinatario(boolean) from public, anon, authenticated;

-- Informe de tutoría ---------------------------------------------------------------------------------------------------

-- Cuestionario del alumnado que contestó un grupo (cada grupo contesta uno solo).
create or replace function privado.cuestionario_grupo(p_grupo integer) returns text
language sql stable security definer set search_path = '' as $$
  select c.codigo from privado.respuesta r join public.cuestionario c on c.id = r.cuestionario_id
  where r.grupo_id = p_grupo and c.colectivo = 'alumnos'
  group by c.codigo order by count(*) desc, c.codigo limit 1;
$$;

revoke execute on function privado.cuestionario_grupo(integer) from public, anon, authenticated;

-- Colectivo de una pregunta en un curso (las de referencia son de un solo colectivo).
create or replace function privado.colectivo_pregunta(p_curso smallint, p_pregunta integer) returns text
language sql stable security definer set search_path = '' as $$
  select min(c.colectivo) from public.pregunta_cuestionario pc join public.cuestionario c on c.id = pc.cuestionario_id
  where pc.pregunta_id = p_pregunta and c.curso_id = p_curso;
$$;

revoke execute on function privado.colectivo_pregunta(smallint, integer) from public, anon, authenticated;

-- Sin comprobar permisos (lo hacen quienes la llaman). La versión la decide el ajuste de siempre.
--   grupo, tutor (null si no tiene) y cuestionario;
--   preguntas: cada pregunta del alumnado sobre su tutor/a en su cuestionario, con el resultado del grupo (el mismo que
--     ve la coordinación en Alumnado con ese grupo) y el de toda la etapa como referencia (todos los tutores);
--   colegio: la labor tutorial según las familias y el personal, el total del Colegio.
-- No hay referencia del Colegio para las preguntas del alumnado: la de PAI y Bachillerato solo existe en esas dos etapas
-- (con el Colegio se deduciría una de la otra, §5 punto 17) y la de Primaria solo en Primaria.
create or replace function privado.informe_tutoria(p_curso text, p_grupo integer)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_curso  smallint := (select id from public.curso where nombre = p_curso);
  v_g      public.grupo;
  v_tutor  public.persona_responsable;
  v_cuest  text;
  v_preg   jsonb := '[]';
  v_ref    jsonb := '[]';
  v_col    text;
  p        record;
begin
  select * into v_g from public.grupo where id = p_grupo and curso_id = v_curso;
  if v_g.id is null then
    raise exception 'Grupo no encontrado' using errcode = 'P0002';
  end if;
  select pr.* into v_tutor from public.tutoria t join public.persona_responsable pr on pr.id = t.persona_id
  where t.curso_id = v_curso and t.grupo_id = p_grupo;
  v_cuest := privado.cuestionario_grupo(p_grupo);

  if v_cuest is not null then
    for p in
      select q.codigo_diccionario, q.texto_es
      from public.tutoria_pregunta tp join public.pregunta q on q.id = tp.pregunta_id
      where tp.curso_id = v_curso and tp.ambito = 'grupo'
        and exists (select 1 from public.pregunta_cuestionario pc join public.cuestionario c on c.id = pc.cuestionario_id
                    where pc.pregunta_id = tp.pregunta_id and c.curso_id = v_curso and c.codigo = v_cuest)
      order by tp.orden, q.codigo_diccionario
    loop
      v_preg := v_preg || jsonb_build_object('codigo', p.codigo_diccionario, 'texto', p.texto_es,
        'grupo', public.resultados(jsonb_build_object('curso', p_curso, 'colectivo', 'alumnos', 'cuestionario', v_cuest, 'grupo', v_g.nombre),
                                   jsonb_build_object('tipo', 'pregunta', 'codigo', p.codigo_diccionario)) -> 'total',
        'etapa', public.resultados(jsonb_build_object('curso', p_curso, 'colectivo', 'alumnos', 'etapa', v_g.etapa),
                                   jsonb_build_object('tipo', 'pregunta', 'codigo', p.codigo_diccionario)) -> 'total');
    end loop;
  end if;

  for p in
    select q.id, q.codigo_diccionario, q.texto_es
    from public.tutoria_pregunta tp join public.pregunta q on q.id = tp.pregunta_id
    where tp.curso_id = v_curso and tp.ambito = 'colegio'
    order by tp.orden, q.codigo_diccionario
  loop
    v_col := privado.colectivo_pregunta(v_curso, p.id);
    continue when v_col is null or v_col = 'alumnos';
    v_ref := v_ref || jsonb_build_object('codigo', p.codigo_diccionario, 'texto', p.texto_es, 'colectivo', v_col,
      'total', public.resultados(jsonb_build_object('curso', p_curso, 'colectivo', v_col),
                                 jsonb_build_object('tipo', 'pregunta', 'codigo', p.codigo_diccionario)) -> 'total');
  end loop;

  return jsonb_build_object(
    'grupo', jsonb_build_object('id', v_g.id, 'nombre', v_g.nombre, 'etapa', v_g.etapa, 'cuestionario', v_cuest),
    'tutor', case when v_tutor.id is not null
                  then jsonb_build_object('id', v_tutor.id, 'nombre', v_tutor.nombre, 'apellidos', v_tutor.apellidos) end,
    'preguntas', v_preg,
    'colegio', v_ref,
    'version', case when privado.ve_menos_de_5() then 'completa' else 'tutor' end);
end $$;

revoke execute on function privado.informe_tutoria(text, integer) from public, anon, authenticated;

-- Grupos del curso para el informe de tutoría: los que tienen respuestas del alumnado o tutor/a.
create or replace function public.listar_tutorias(p_curso text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_curso smallint := (select id from public.curso where nombre = p_curso);
begin
  perform permisos.exigir();
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a los informes de tutoría' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', g.id, 'nombre', g.nombre, 'etapa', g.etapa, 'nivel', g.nivel,
             'con_respuestas', exists (select 1 from privado.respuesta r where r.grupo_id = g.id),
             'tutor', case when pr.id is not null then jsonb_build_object('id', pr.id, 'nombre', pr.nombre, 'apellidos', pr.apellidos) end)
           order by array_position(array['infantil', 'primaria', 'pai', 'bachillerato'], g.etapa),
                    nullif(regexp_replace(g.nivel, '\D', '', 'g'), '')::integer, g.nombre)
    from public.grupo g
    left join public.tutoria t on t.grupo_id = g.id and t.curso_id = v_curso
    left join public.persona_responsable pr on pr.id = t.persona_id
    where g.curso_id = v_curso
      and (t.persona_id is not null or exists (select 1 from privado.respuesta r where r.grupo_id = g.id))
  ), '[]');
end $$;

revoke execute on function public.listar_tutorias(text) from public, anon;
grant execute on function public.listar_tutorias(text) to authenticated;

-- Informe de tutoría para Dirección y administración: «completa» o «tutor» (la que recibe el tutor/a).
create or replace function public.informe_tutoria(p_curso text, p_grupo integer, p_registrar boolean default false,
                                                   p_version text default 'completa')
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_previo text;
  v_inf    jsonb;
begin
  perform permisos.exigir();
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a los informes de tutoría' using errcode = '42501';
  end if;
  if p_version is null or p_version not in ('completa', 'tutor') then
    raise exception 'Versión del informe no válida' using errcode = '22023';
  end if;
  v_previo := privado.version_destinatario(p_version = 'tutor');
  v_inf := privado.informe_tutoria(p_curso, p_grupo);
  perform set_config('encuestas.version_docente', v_previo, true);
  if p_registrar then
    perform privado.registrar('informe_responsable', jsonb_build_object('curso', p_curso, 'tipo', 'tutoria',
      'ambito', v_inf -> 'grupo' ->> 'nombre', 'version', p_version));
  end if;
  return v_inf;
end $$;

revoke execute on function public.informe_tutoria(text, integer, boolean, text) from public, anon;
grant execute on function public.informe_tutoria(text, integer, boolean, text) to authenticated;

-- Informe de servicio -------------------------------------------------------------------------------------------------

-- Sin comprobar permisos. Por colectivo (alumnado, familias, personal), cada pregunta del servicio: alumnado y familias con
-- el total y cada etapa (la misma tabla que ve Dirección en Alumnado o Familias repartida por etapa, con la supresión
-- conjunta); el personal, solo el total. Como referencia, la media del bloque de servicios de cada colectivo.
create or replace function privado.informe_servicio(p_curso text, p_servicio integer)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_curso  smallint := (select id from public.curso where nombre = p_curso);
  v_s      public.servicio;
  v_resp   public.persona_responsable;
  v_cols   jsonb := '[]';
  v_preg   jsonb;
  v_r      jsonb;
  v_ref    jsonb;
  v_col    text;
  p        record;
begin
  select * into v_s from public.servicio where id = p_servicio and curso_id = v_curso;
  if v_s.id is null then
    raise exception 'Servicio no encontrado' using errcode = 'P0002';
  end if;
  select pr.* into v_resp from public.responsable_servicio rs join public.persona_responsable pr on pr.id = rs.persona_id
  where rs.servicio_id = p_servicio;

  foreach v_col in array array['alumnos', 'familias', 'personal'] loop
    v_preg := '[]';
    for p in
      select q.codigo_diccionario, q.texto_es, sp.principal
      from public.servicio_pregunta sp join public.pregunta q on q.id = sp.pregunta_id
      where sp.servicio_id = p_servicio
        and exists (select 1 from public.pregunta_cuestionario pc join public.cuestionario c on c.id = pc.cuestionario_id
                    where pc.pregunta_id = q.id and c.curso_id = v_curso and c.colectivo = v_col)
      order by sp.principal desc, sp.orden, q.codigo_diccionario
    loop
      v_r := public.resultados(jsonb_build_object('curso', p_curso, 'colectivo', v_col),
                               jsonb_build_object('tipo', 'pregunta', 'codigo', p.codigo_diccionario),
                               case when v_col = 'personal' then '{}'::text[] else '{etapa}'::text[] end);
      v_preg := v_preg || jsonb_build_object('codigo', p.codigo_diccionario, 'texto', p.texto_es, 'principal', p.principal,
        'total', v_r -> 'total',
        -- Las respuestas sin etapa no son una parte que se enseñe (§5 punto 6): cuentan en el total y en la supresión.
        'etapas', coalesce((select jsonb_agg(x order by array_position(array['infantil', 'primaria', 'pai', 'bachillerato'], x -> 'clave' ->> 'etapa'))
                            from jsonb_array_elements(v_r -> 'partes') x where x -> 'clave' ->> 'etapa' <> '(sin dato)'), '[]'));
    end loop;
    continue when jsonb_array_length(v_preg) = 0;
    v_ref := null;
    if exists (select 1 from public.bloque b join public.cuestionario c on c.id = b.cuestionario_id
               where c.curso_id = v_curso and c.colectivo = v_col and b.codigo = 'servicios') then
      v_ref := public.resultados(jsonb_build_object('curso', p_curso, 'colectivo', v_col), '{"tipo": "bloque", "codigo": "servicios"}') -> 'total';
    end if;
    v_cols := v_cols || jsonb_build_object('colectivo', v_col, 'preguntas', v_preg, 'servicios', v_ref);
  end loop;

  return jsonb_build_object(
    'servicio', jsonb_build_object('id', v_s.id, 'codigo', v_s.codigo, 'nombre', v_s.nombre),
    'responsable', case when v_resp.id is not null
                        then jsonb_build_object('id', v_resp.id, 'nombre', v_resp.nombre, 'apellidos', v_resp.apellidos) end,
    'colectivos', v_cols,
    'version', case when privado.ve_menos_de_5() then 'completa' else 'responsable' end);
end $$;

revoke execute on function privado.informe_servicio(text, integer) from public, anon, authenticated;

-- Servicios del curso con su responsable. El correo solo para administración, que es quien mantiene la lista.
create or replace function public.listar_servicios(p_curso text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_perfil public.usuario_perfil := permisos.exigir();
  v_curso  smallint := (select id from public.curso where nombre = p_curso);
begin
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a los informes de servicios' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'codigo', s.codigo, 'nombre', s.nombre,
             'colectivos', (select coalesce(jsonb_agg(distinct c.colectivo), '[]')
                            from public.servicio_pregunta sp join public.pregunta_cuestionario pc on pc.pregunta_id = sp.pregunta_id
                            join public.cuestionario c on c.id = pc.cuestionario_id
                            where sp.servicio_id = s.id and c.curso_id = v_curso),
             'responsable', case when pr.id is not null then jsonb_strip_nulls(jsonb_build_object('id', pr.id, 'nombre', pr.nombre,
               'apellidos', pr.apellidos, 'correo', case when v_perfil.rol = 'administrador' then pr.correo end)) end)
           order by s.orden, s.nombre)
    from public.servicio s
    left join public.responsable_servicio rs on rs.servicio_id = s.id
    left join public.persona_responsable pr on pr.id = rs.persona_id
    where s.curso_id = v_curso
  ), '[]');
end $$;

revoke execute on function public.listar_servicios(text) from public, anon;
grant execute on function public.listar_servicios(text) to authenticated;

create or replace function public.informe_servicio(p_curso text, p_servicio integer, p_registrar boolean default false,
                                                    p_version text default 'completa')
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_previo text;
  v_inf    jsonb;
begin
  perform permisos.exigir();
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a los informes de servicios' using errcode = '42501';
  end if;
  if p_version is null or p_version not in ('completa', 'responsable') then
    raise exception 'Versión del informe no válida' using errcode = '22023';
  end if;
  v_previo := privado.version_destinatario(p_version = 'responsable');
  v_inf := privado.informe_servicio(p_curso, p_servicio);
  perform set_config('encuestas.version_docente', v_previo, true);
  if p_registrar then
    perform privado.registrar('informe_responsable', jsonb_build_object('curso', p_curso, 'tipo', 'servicio',
      'ambito', v_inf -> 'servicio' ->> 'nombre', 'version', p_version));
  end if;
  return v_inf;
end $$;

revoke execute on function public.informe_servicio(text, integer, boolean, text) from public, anon;
grant execute on function public.informe_servicio(text, integer, boolean, text) to authenticated;

-- Responsable de un servicio: solo administración, desde la aplicación. La persona se busca por su correo; si no
-- existe (personal no docente), se crea. Queda en el registro de actividad.
create or replace function public.admin_servicio_responsable(p_curso text, p_servicio integer, p_nombre text, p_apellidos text,
                                                              p_correo text)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_yo      public.usuario_perfil := privado.exigir_admin();
  v_curso   smallint := (select id from public.curso where nombre = p_curso);
  v_s       public.servicio;
  v_correo  text := lower(btrim(coalesce(p_correo, '')));
  v_persona public.persona_responsable;
begin
  select * into v_s from public.servicio where id = p_servicio and curso_id = v_curso;
  if v_s.id is null then
    raise exception 'Servicio no encontrado' using errcode = 'P0002';
  end if;
  if v_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_correo) > 200 then
    raise exception 'Correo no válido' using errcode = '22023';
  end if;
  select * into v_persona from public.persona_responsable where lower(correo) = v_correo;
  if v_persona.id is null then
    if coalesce(btrim(p_nombre), '') = '' or coalesce(btrim(p_apellidos), '') = ''
       or length(p_nombre) > 100 or length(p_apellidos) > 200 then
      raise exception 'Escribe el nombre y los apellidos' using errcode = '22023';
    end if;
    insert into public.persona_responsable (nombre, apellidos, correo) values (btrim(p_nombre), btrim(p_apellidos), v_correo)
      returning * into v_persona;
  end if;
  insert into public.responsable_servicio (servicio_id, persona_id, actualizado_por) values (p_servicio, v_persona.id, v_yo.id)
    on conflict (servicio_id) do update set persona_id = excluded.persona_id, actualizado = now(), actualizado_por = excluded.actualizado_por;
  perform privado.registrar('responsable_servicio', jsonb_build_object('curso', p_curso, 'servicio', v_s.nombre,
    'persona', v_persona.id, 'nombre', v_persona.nombre || ' ' || v_persona.apellidos, 'correo', v_persona.correo));
  return jsonb_build_object('id', v_persona.id, 'nombre', v_persona.nombre, 'apellidos', v_persona.apellidos, 'correo', v_persona.correo);
end $$;

create or replace function public.admin_servicio_responsable_quitar(p_curso text, p_servicio integer)
returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_curso  smallint := (select id from public.curso where nombre = p_curso);
  v_s      public.servicio;
  v_pid    integer;
begin
  perform privado.exigir_admin();
  select * into v_s from public.servicio where id = p_servicio and curso_id = v_curso;
  if v_s.id is null then
    raise exception 'Servicio no encontrado' using errcode = 'P0002';
  end if;
  delete from public.responsable_servicio where servicio_id = p_servicio returning persona_id into v_pid;
  if v_pid is not null then
    perform privado.registrar('responsable_servicio_quitar', jsonb_build_object('curso', p_curso, 'servicio', v_s.nombre,
      'persona', v_pid, 'nombre', (select nombre || ' ' || apellidos from public.persona_responsable where id = v_pid)));
  end if;
end $$;

revoke execute on function public.admin_servicio_responsable(text, integer, text, text, text),
  public.admin_servicio_responsable_quitar(text, integer) from public, anon;
grant execute on function public.admin_servicio_responsable(text, integer, text, text, text),
  public.admin_servicio_responsable_quitar(text, integer) to authenticated;

-- Envío en un paso ----------------------------------------------------------------------------------------------------

-- Selección: {"informe": "profesor" | "jefatura_departamento" | "jefatura_equipo" | "tutoria" | "servicio",
--             "filtro": {"tipo": ..., "valores": [...]}} (sin filtro: todos sus destinatarios). Filtros de cada informe:
--   profesor: todos, docente, departamento, etapa o tramo (los de siempre);
--   jefatura_departamento: todos o persona;  jefatura_equipo: todos, persona o tramo;
--   tutoria: todos, etapa, grupo o persona (tutor/a);  servicio: todos o servicio.
-- Se siguen aceptando las selecciones anteriores ({"tipo": "docente" | ... | "jefaturas", "valores": [...]}).
--
-- Una fila por informe, también los que no tienen a quién enviarse (grupo sin tutor/a, servicio sin responsable):
--   clave: identifica el informe (para quitarlo del envío y para comprobar si tiene resultados visibles);
--   aviso: sin_destinatario, sin_resultados o sin_correo (se queda fuera);
--   ya_enviado: fecha del último enlace enviado y no anulado de ese informe (en el mismo modo: prueba o de verdad).
drop function if exists public.admin_envio_destinatarios(text, jsonb, text);
drop function if exists public.admin_envio_crear(text, jsonb, text);
drop function if exists privado.destinatarios(smallint, jsonb, text);

create or replace function privado.destinatarios(p_curso smallint, p_seleccion jsonb, p_correo_prueba text)
returns table (clave text, persona_id integer, tipo text, tramo text, grupo_id integer, servicio_id integer, informe text,
               nombre text, apellidos text, departamento text, correo text, destinatario text, aviso text, ya_enviado timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_modo     text := (select modo from privado.configuracion_envio);
  v_prueba   text := nullif(lower(btrim(coalesce(p_correo_prueba, ''))), '');
  v_sel      jsonb := coalesce(p_seleccion, '{}');
  v_informes text[];
  v_filtro   jsonb;
  v_ftipo    text;
  v_valores  text[];
  v_validos  text[];
  v_docentes integer[] := '{}';
begin
  if v_prueba is not null and not privado.correo_niage(v_prueba) then
    raise exception 'El correo de prueba tiene que ser de Niage (@niage.es o @niage.eu)' using errcode = '22023';
  end if;
  if v_modo = 'pruebas' and v_prueba is null then
    raise exception 'Envío en modo de pruebas: indica un correo de Niage. No se envía nada al profesorado.' using errcode = '22023';
  end if;

  if v_sel ? 'informe' then
    v_informes := array[v_sel ->> 'informe'];
    v_filtro := coalesce(v_sel -> 'filtro', '{"tipo": "todos"}');
  elsif v_sel ->> 'tipo' = 'jefaturas' then
    v_informes := array['jefatura_departamento', 'jefatura_equipo'];
    v_filtro := case when jsonb_array_length(coalesce(v_sel -> 'valores', '[]')) > 0
                     then jsonb_build_object('tipo', 'persona', 'valores', v_sel -> 'valores') else '{"tipo": "todos"}' end;
  else
    v_informes := array['profesor'];
    v_filtro := v_sel;
  end if;
  v_ftipo := coalesce(v_filtro ->> 'tipo', 'todos');
  v_valores := array(select jsonb_array_elements_text(coalesce(v_filtro -> 'valores', '[]')));

  if cardinality(v_informes) = 1 then
    v_validos := case v_informes[1]
      when 'profesor' then array['todos', 'docente', 'departamento', 'etapa', 'tramo']
      when 'jefatura_departamento' then array['todos', 'persona']
      when 'jefatura_equipo' then array['todos', 'persona', 'tramo']
      when 'tutoria' then array['todos', 'etapa', 'grupo', 'persona']
      when 'servicio' then array['todos', 'servicio'] end;
    if v_validos is null then
      raise exception 'Tipo de informe no válido' using errcode = '22023';
    end if;
    if not v_ftipo = any(v_validos) then
      raise exception 'Selección no válida' using errcode = '22023';
    end if;
  end if;
  if v_ftipo <> 'todos' and cardinality(v_valores) = 0 then
    raise exception 'Elige al menos un valor' using errcode = '22023';
  end if;
  if 'profesor' = any(v_informes) then
    v_docentes := array(select s.docente_id from privado.docentes_seleccion(p_curso, v_filtro) s);
  end if;

  return query
  with filas as (
    select s.docente_id as pid, 'profesor'::text as tipo, null::text as tramo, null::integer as gid, null::integer as sid,
           null::text as informe, not privado.tiene_informe(p_curso, s.docente_id) as sin_informe, 0 as ord
    from unnest(v_docentes) s(docente_id)
    union all
    select ca.persona_id, 'jefatura_departamento', null, null, null, string_agg(ca.ambito, ', ' order by ca.ambito), false, 0
    from public.cargo ca
    where 'jefatura_departamento' = any(v_informes) and ca.curso_id = p_curso and ca.tipo = 'jefe_departamento'
      and (v_ftipo = 'todos' or ca.persona_id::text = any(v_valores))
    group by ca.persona_id
    union all
    select ca.persona_id, 'jefatura_equipo', ca.ambito, null, null, ca.ambito, false,
           array_position(array['infantil', 'y1_y5', 'y6_y9', 'y10_y12'], ca.ambito)
    from public.cargo ca
    where 'jefatura_equipo' = any(v_informes) and ca.curso_id = p_curso and ca.tipo = 'jefe_equipo'
      and (v_ftipo = 'todos' or (v_ftipo = 'persona' and ca.persona_id::text = any(v_valores))
           or (v_ftipo = 'tramo' and ca.ambito = any(v_valores)))
    union all
    select t.persona_id, 'tutoria', null, g.id, null, g.nombre,
           not exists (select 1 from privado.respuesta r join public.cuestionario c on c.id = r.cuestionario_id
                       where r.grupo_id = g.id and c.colectivo = 'alumnos'),
           array_position(array['infantil', 'primaria', 'pai', 'bachillerato'], g.etapa) * 100
             + coalesce(nullif(regexp_replace(g.nivel, '\D', '', 'g'), '')::integer, 0)
    from public.grupo g
    left join public.tutoria t on t.grupo_id = g.id and t.curso_id = p_curso
    where 'tutoria' = any(v_informes) and g.curso_id = p_curso
      and (t.persona_id is not null or exists (select 1 from privado.respuesta r where r.grupo_id = g.id))
      and (v_ftipo = 'todos' or (v_ftipo = 'etapa' and g.etapa = any(v_valores)) or (v_ftipo = 'grupo' and g.id::text = any(v_valores))
           or (v_ftipo = 'persona' and t.persona_id::text = any(v_valores)))
    union all
    select rs.persona_id, 'servicio', null, null, s.id, s.nombre, false, s.orden::integer
    from public.servicio s
    left join public.responsable_servicio rs on rs.servicio_id = s.id
    where 'servicio' = any(v_informes) and s.curso_id = p_curso
      and (v_ftipo = 'todos' or s.id::text = any(v_valores))
  )
  select concat_ws(':', f.tipo, coalesce(f.pid::text, '-'), coalesce(f.tramo, ''), coalesce(f.gid::text, ''), coalesce(f.sid::text, '')),
         f.pid, f.tipo, f.tramo, f.gid, f.sid, f.informe, pr.nombre, pr.apellidos, dep.nombre, pr.correo,
         case when f.pid is null then null when v_prueba is not null then v_prueba else lower(btrim(pr.correo)) end,
         case when f.pid is null then 'sin_destinatario'
              when f.sin_informe then 'sin_resultados'
              when v_prueba is null and coalesce(btrim(pr.correo), '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then 'sin_correo' end,
         (select max(e.enviado) from privado.enlace_informe e
          where e.curso_id = p_curso and e.tipo = f.tipo and e.persona_id = f.pid and e.tramo is not distinct from f.tramo
            and e.grupo_id is not distinct from f.gid and e.servicio_id is not distinct from f.sid
            and e.anulado is null and e.enviado is not null and e.prueba = (v_prueba is not null))
  from filas f
  left join public.persona_responsable pr on pr.id = f.pid
  left join public.departamento dep on dep.id = pr.departamento_id
  order by array_position(array['profesor', 'jefatura_departamento', 'jefatura_equipo', 'tutoria', 'servicio'], f.tipo),
           case when f.tipo in ('tutoria', 'servicio') then null else pr.apellidos end,
           case when f.tipo in ('tutoria', 'servicio') then null else pr.nombre end,
           f.ord, f.informe;
end $$;

revoke execute on function privado.destinatarios(smallint, jsonb, text) from public, anon, authenticated;

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

-- Crea los enlaces (uno por informe con destinatario, resultados y correo, menos los que se quitan en la vista previa)
-- y deja los correos listos para la Edge Function.
create or replace function public.admin_envio_crear(p_curso text, p_seleccion jsonb, p_correo_prueba text default null,
                                                     p_excluir text[] default '{}')
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_perfil  public.usuario_perfil := privado.exigir_admin();
  v_curso   smallint := (select id from public.curso where nombre = p_curso);
  v_conf    privado.configuracion_envio := (select c from privado.configuracion_envio c);
  v_prueba  boolean := nullif(btrim(coalesce(p_correo_prueba, '')), '') is not null;
  v_excluir text[] := coalesce(p_excluir, '{}');
  v_envio   bigint;
  v_n       integer := 0;
  v_fuera   integer := 0;
  v_quitados integer := 0;
  v_token   text;
  d         record;
begin
  if v_curso is null then raise exception 'Curso no encontrado' using errcode = 'P0002'; end if;
  insert into privado.envio (curso_id, creado_por, seleccion, prueba) values (v_curso, v_perfil.id, p_seleccion, v_prueba)
    returning id into v_envio;
  for d in select * from privado.destinatarios(v_curso, p_seleccion, p_correo_prueba) loop
    if d.aviso is not null then v_fuera := v_fuera + 1; continue; end if;
    if d.clave = any(v_excluir) then v_quitados := v_quitados + 1; continue; end if;
    if v_conf.modo = 'pruebas' and not privado.correo_niage(d.destinatario) then
      raise exception 'Modo de pruebas: solo correos de Niage' using errcode = '42501';
    end if;
    v_token := translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/=', '-_');
    insert into privado.enlace_informe (envio_id, curso_id, persona_id, tipo, tramo, grupo_id, servicio_id, destinatario, prueba,
                                        token_hash, token, caduca)
      values (v_envio, v_curso, d.persona_id, d.tipo, d.tramo, d.grupo_id, d.servicio_id, d.destinatario, v_prueba,
              privado.huella(v_token), v_token, now() + make_interval(days => v_conf.dias));
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then
    raise exception 'Nadie de la selección tiene informe y correo' using errcode = '22023';
  end if;
  perform privado.registrar('envio_informes', jsonb_build_object('curso', p_curso, 'envio', v_envio::text, 'seleccion', p_seleccion,
    'enlaces', v_n, 'fuera', v_fuera, 'quitados', v_quitados, 'prueba', v_prueba,
    'correo_prueba', case when v_prueba then lower(btrim(p_correo_prueba)) end));
  return jsonb_build_object('envio', v_envio::text, 'enlaces', v_n, 'fuera', v_fuera, 'quitados', v_quitados, 'prueba', v_prueba);
end $$;

revoke execute on function public.admin_envio_destinatarios(text, jsonb, text), public.admin_envio_crear(text, jsonb, text, text[])
  from public, anon;
grant execute on function public.admin_envio_destinatarios(text, jsonb, text), public.admin_envio_crear(text, jsonb, text, text[])
  to authenticated;

-- ¿Tendría el destinatario algún resultado visible en su versión? Para la vista previa, por tandas (el informe del
-- profesor/a tarda): recibe claves de privado.destinatarios y devuelve {clave: true | false}. Solo administración.
create or replace function public.admin_envio_visibles(p_curso text, p_claves text[])
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_curso  smallint := (select id from public.curso where nombre = p_curso);
  v_previo text;
  v_res    jsonb := '{}';
  v_k      text;
  v_p      text[];
  v_inf    jsonb;
  v_vis    boolean;
begin
  perform privado.exigir_admin();
  if v_curso is null then raise exception 'Curso no encontrado' using errcode = 'P0002'; end if;
  if p_claves is null or cardinality(p_claves) > 25 then
    raise exception 'Como mucho 25 informes a la vez' using errcode = '22023';
  end if;
  v_previo := privado.version_destinatario(true);
  foreach v_k in array p_claves loop
    v_p := string_to_array(v_k, ':');
    continue when cardinality(v_p) <> 5 or v_p[2] !~ '^\d+$';
    v_vis := false;
    if v_p[1] = 'profesor' then
      v_inf := privado.informe_profesor(v_curso, v_p[2]::integer, null);
      v_vis := not coalesce((v_inf -> 'global' ->> 'suprimido')::boolean, true)
               or exists (select 1 from jsonb_array_elements(coalesce(v_inf -> 'celdas', '[]')) c where not (c ->> 'suprimido')::boolean);
    elsif v_p[1] = 'jefatura_departamento' then
      v_inf := privado.informe_jefatura_departamento(p_curso, v_p[2]::integer);
      v_vis := exists (select 1 from jsonb_array_elements(v_inf -> 'reuniones') x where not (x -> 'total' ->> 'suprimido')::boolean)
               or not coalesce((v_inf -> 'alumnos' -> 'media' -> 'global' ->> 'suprimido')::boolean, true);
    elsif v_p[1] = 'jefatura_equipo' and v_p[3] in ('infantil', 'y1_y5', 'y6_y9', 'y10_y12') then
      v_inf := privado.informe_jefatura_equipo(p_curso, array[v_p[3]], true);
      v_vis := not coalesce((v_inf -> 'total' ->> 'suprimido')::boolean, true);
    elsif v_p[1] = 'tutoria' and v_p[4] ~ '^\d+$' then
      v_inf := privado.informe_tutoria(p_curso, v_p[4]::integer);
      v_vis := exists (select 1 from jsonb_array_elements(v_inf -> 'preguntas') x where not (x -> 'grupo' ->> 'suprimido')::boolean);
    elsif v_p[1] = 'servicio' and v_p[5] ~ '^\d+$' then
      v_inf := privado.informe_servicio(p_curso, v_p[5]::integer);
      v_vis := exists (select 1 from jsonb_array_elements(v_inf -> 'colectivos') c, jsonb_array_elements(c -> 'preguntas') x
                       where not (x -> 'total' ->> 'suprimido')::boolean);
    else
      continue;
    end if;
    v_res := v_res || jsonb_build_object(v_k, v_vis);
  end loop;
  perform set_config('encuestas.version_docente', v_previo, true);
  return v_res;
end $$;

revoke execute on function public.admin_envio_visibles(text, text[]) from public, anon;
grant execute on function public.admin_envio_visibles(text, text[]) to authenticated;

-- Para la Edge Function: añade el grupo y el servicio (para el texto del correo).
create or replace function public.envio_pendientes(p_envio bigint)
returns jsonb
language sql volatile security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'enlace', e.id::text, 'token', e.token, 'destinatario', e.destinatario, 'prueba', e.prueba, 'caduca', e.caduca,
    'tipo', e.tipo, 'tramo', e.tramo,
    'grupo', (select g.nombre from public.grupo g where g.id = e.grupo_id),
    'servicio', (select s.nombre from public.servicio s where s.id = e.servicio_id),
    'nombre', pr.nombre, 'apellidos', pr.apellidos, 'correo_docente', pr.correo, 'curso', cu.nombre,
    'modo', (select modo from privado.configuracion_envio))), '[]')
  from privado.enlace_informe e
  join public.persona_responsable pr on pr.id = e.persona_id
  join public.curso cu on cu.id = e.curso_id
  where e.envio_id = p_envio and e.enviado is null and e.error is null and e.token is not null and e.anulado is null;
$$;

revoke execute on function public.envio_pendientes(bigint) from public, anon, authenticated;
grant execute on function public.envio_pendientes(bigint) to service_role;

-- Enlaces enviados del curso: también el grupo y el servicio.
create or replace function public.admin_envios(p_curso text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', e.id::text, 'docente', pr.nombre || ' ' || pr.apellidos, 'tipo', e.tipo, 'tramo', e.tramo,
      'grupo', (select g.nombre from public.grupo g where g.id = e.grupo_id),
      'servicio', (select s.nombre from public.servicio s where s.id = e.servicio_id),
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

-- Enlace personal: el tutor/a abre la versión para el tutor/a de su grupo y el responsable, la de su servicio.
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
    when 'jefatura_equipo' then privado.informe_jefatura_equipo(v_curso, array[v_e.tramo], true) || '{"version": "jefatura"}'
    when 'tutoria' then privado.informe_tutoria(v_curso, v_e.grupo_id)
    else privado.informe_servicio(v_curso, v_e.servicio_id) end;
  perform set_config('encuestas.enlace', '', true);
  return jsonb_build_object('estado', 'ok', 'caduca', v_e.caduca, 'curso', v_curso, 'tipo', v_e.tipo,
    'profesor', jsonb_build_object('nombre', v_pr.nombre, 'apellidos', v_pr.apellidos, 'departamento', v_dep),
    'informe', v_informe);
end $$;

-- Descarga del PDF desde el enlace: también el de tutoría y el de servicio.
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
            'tipo', case v_e.tipo when 'profesor' then 'informe_profesor' when 'jefatura_departamento' then 'informe_jefatura'
                                  when 'jefatura_equipo' then 'informe_equipo' when 'tutoria' then 'informe_tutoria' else 'informe_servicio' end,
            'curso', (select nombre from public.curso where id = v_e.curso_id), 'objeto', v_nombre,
            'docente', case when v_e.tipo = 'profesor' then v_pr.id end, 'persona', case when v_e.tipo <> 'profesor' then v_pr.id end,
            'tramos', case when v_e.tramo is not null then jsonb_build_array(v_e.tramo) end,
            'grupo', (select g.nombre from public.grupo g where g.id = v_e.grupo_id),
            'servicio', (select s.nombre from public.servicio s where s.id = v_e.servicio_id),
            'archivo', left(coalesce(p_archivo, ''), 200),
            'version', case v_e.tipo when 'profesor' then 'docente' when 'tutoria' then 'tutor' when 'servicio' then 'responsable' else 'jefatura' end,
            'enlace', v_e.id::text, 'nombre', v_nombre)), v_fecha);
  return jsonb_build_object('codigo', v_codigo, 'nombre', v_nombre, 'fecha', v_fecha, 'informes', '[]'::jsonb);
end $$;

revoke execute on function public.informe_enlace(text), public.descarga_enlace(text, text) from public;
grant execute on function public.informe_enlace(text), public.descarga_enlace(text, text) to anon, authenticated;

-- Registro de descargas: los dos informes nuevos (solo Dirección y administración) y sus versiones.
create or replace function public.registrar_descarga(p_tipo text, p_datos jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_perfil public.usuario_perfil := permisos.exigir();
  v_datos jsonb := coalesce(p_datos, '{}');
  v_codigo text;
  v_usados text[] := '{}';
  v_informes jsonb := '[]';
  v_fecha timestamptz := now();
  x jsonb;
begin
  if p_tipo is null or p_tipo not in ('informe_profesor', 'informe_jefatura', 'informe_equipo', 'informe_direccion',
                                      'informe_tutoria', 'informe_servicio', 'vista_pdf', 'csv', 'zip') then
    raise exception 'Tipo de descarga no válido' using errcode = '22023';
  end if;
  if jsonb_typeof(v_datos) <> 'object' or length(v_datos::text) > 60000
     or (v_datos ? 'filtros' and jsonb_typeof(v_datos -> 'filtros') <> 'object')
     or coalesce(btrim(v_datos ->> 'objeto'), '') = '' or length(v_datos ->> 'objeto') > 300 then
    raise exception 'Datos de la descarga no válidos' using errcode = '22023';
  end if;
  -- Lo que cada rol puede descargar (los datos ya los ha filtrado la RPC de cada informe o vista).
  if v_perfil.rol = 'coordinacion' and p_tipo in ('informe_jefatura', 'informe_equipo', 'informe_direccion', 'informe_tutoria', 'informe_servicio') then
    raise exception 'Sin acceso a los informes de responsables' using errcode = '42501';
  end if;
  if p_tipo in ('vista_pdf', 'csv') then
    if coalesce(v_datos ->> 'vista', '') not in ('inicio', 'alumnos', 'familias', 'personal', 'descargas', 'abiertas') then
      raise exception 'Vista de exportación no válida' using errcode = '22023';
    end if;
    if v_datos ->> 'vista' = 'personal' and v_perfil.rol = 'coordinacion' then
      raise exception 'Sin acceso a los resultados de personal' using errcode = '42501';
    end if;
    if v_datos ->> 'vista' = 'abiertas' and v_perfil.rol not in ('direccion', 'administrador') then
      raise exception 'Las respuestas abiertas solo las ven Dirección y administración' using errcode = '42501';
    end if;
    if v_datos ->> 'vista' = 'descargas' and v_perfil.rol <> 'administrador' then
      raise exception 'Solo para administración' using errcode = '42501';
    end if;
  end if;
  if p_tipo = 'zip' then
    if coalesce(jsonb_typeof(v_datos -> 'informes'), '') <> 'array' or jsonb_array_length(v_datos -> 'informes') = 0
       or jsonb_array_length(v_datos -> 'informes') > 500 then
      raise exception 'Un ZIP necesita la lista de sus informes' using errcode = '22023';
    end if;
    for x in select * from jsonb_array_elements(v_datos -> 'informes') loop
      if jsonb_typeof(x) <> 'object' or coalesce(btrim(x ->> 'objeto'), '') = '' then
        raise exception 'Datos de la descarga no válidos' using errcode = '22023';
      end if;
      v_codigo := privado.codigo_descarga_libre(v_usados);
      v_usados := v_usados || v_codigo;
      v_informes := v_informes || jsonb_build_object('objeto', x ->> 'objeto', 'docente', x -> 'docente', 'codigo', v_codigo);
    end loop;
  end if;
  v_codigo := privado.codigo_descarga_libre(v_usados);

  perform privado.registrar('descarga', jsonb_strip_nulls(jsonb_build_object(
    'codigo', v_codigo, 'tipo', p_tipo, 'curso', v_datos ->> 'curso', 'objeto', btrim(v_datos ->> 'objeto'),
    'docente', v_datos -> 'docente', 'persona', v_datos -> 'persona', 'tramos', v_datos -> 'tramos', 'vista', v_datos ->> 'vista',
    'grupo', left(v_datos ->> 'grupo', 50), 'servicio', left(v_datos ->> 'servicio', 100),
    'filtros', nullif(coalesce(v_datos -> 'filtros', '{}'), '{}'), 'archivo', v_datos ->> 'archivo',
    'version', case when v_datos ->> 'version' in ('completa', 'docente', 'jefatura', 'tutor', 'responsable') then v_datos ->> 'version' end,
    'informes', case when p_tipo = 'zip' then v_informes end,
    'nombre', v_perfil.nombre)));
  return jsonb_build_object('codigo', v_codigo, 'nombre', v_perfil.nombre, 'fecha', v_fecha, 'informes', v_informes);
end $$;
