-- Respuestas del colegio del 21/10/2026 (§4, §5.9, §5.12 a §5.14, §7.2 y §7.3):
--
-- 1. Departamentos oficiales y su equivalencia con los de la encuesta de personal. La matriz
--    de reuniones de 2025/26 nombra departamentos que no coinciden con los oficiales: uno se
--    llama distinto y otro («Inglés y Adquisición de Lenguas») cubre dos oficiales.
-- 2. Tramo de tutoría (infantil, y1_y5, y6_y9, y10_y12), solo para el bloque del Equipo de
--    Individuación. Es una dimensión aislada, como el departamento de las reuniones: no se
--    cruza con ninguna otra respuesta ni filtro.
-- 3. Atribución de respuestas de alumnos a un docente por el nombre que escribieron (o por la
--    optativa). Solo se guarda el docente resultante, nunca el texto.
-- 4. Clases propias y compartidas en el informe del profesor: la media global sale solo de
--    las propias (y de los subconjuntos atribuidos a él).
-- 5. Informe de departamento por jefe y del Equipo de Individuación por jefe de equipo. Las
--    partes ocultas de un mismo responsable se pueden mostrar juntas si cada una está oculta
--    por separado (nunca si una se ve y otra no: la resta destaparía la oculta).

-- 1. Departamentos -------------------------------------------------------------------------

alter table public.departamento add column oficial boolean not null default true;

-- Departamento tal como aparece en la encuesta (con respuestas) → departamento oficial. Sin
-- fila, un departamento de la encuesta equivale a sí mismo.
create table public.departamento_equivalencia (
  departamento_encuesta_id  integer not null references public.departamento on delete cascade,
  departamento_id           integer not null references public.departamento on delete cascade,
  primary key (departamento_encuesta_id, departamento_id)
);
alter table public.departamento_equivalencia enable row level security;
revoke all on public.departamento_equivalencia from anon;
revoke insert, update, delete, truncate on public.departamento_equivalencia from authenticated;
create policy lectura_usuarios_activos on public.departamento_equivalencia
  for select to authenticated using (permisos.activo());

alter table public.persona_responsable
  add column situacion text not null default 'alta' check (situacion in ('alta', 'baja'));

-- 2. Tramo de tutoría ------------------------------------------------------------------------

create table privado.respuesta_tramo (
  respuesta_id  bigint primary key references privado.respuesta on delete cascade,
  tramo         text not null check (tramo in ('infantil', 'y1_y5', 'y6_y9', 'y10_y12'))
);

create function privado.validar_respuesta_tramo() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (
    select 1 from privado.respuesta r join public.cuestionario c on c.id = r.cuestionario_id
    where r.id = new.respuesta_id and c.colectivo = 'personal'
  ) then
    raise exception 'El tramo de tutoría solo existe en personal';
  end if;
  return new;
end $$;

create trigger respuesta_tramo_validar
  before insert or update on privado.respuesta_tramo
  for each row execute function privado.validar_respuesta_tramo();

-- 3. Atribución a un docente ----------------------------------------------------------------

create table privado.respuesta_docente (
  respuesta_id   bigint not null references privado.respuesta on delete cascade,
  asignatura_id  integer not null references public.asignatura,
  docente_id     integer not null references public.persona_responsable on delete cascade,
  primary key (respuesta_id, asignatura_id)
);
create index on privado.respuesta_docente (docente_id);

create function privado.validar_respuesta_docente() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (
    select 1 from privado.respuesta r join public.cuestionario c on c.id = r.cuestionario_id
    where r.id = new.respuesta_id and c.colectivo = 'alumnos'
  ) then
    raise exception 'La atribución a un docente solo existe en alumnos';
  end if;
  return new;
end $$;

create trigger respuesta_docente_validar
  before insert or update on privado.respuesta_docente
  for each row execute function privado.validar_respuesta_docente();

do $$
declare t text;
begin
  foreach t in array array['respuesta_tramo', 'respuesta_docente'] loop
    execute format('alter table privado.%I enable row level security', t);
    execute format('revoke all on privado.%I from public, anon, authenticated', t);
    execute format('grant select, insert, update, delete on privado.%I to service_role', t);
  end loop;
end $$;

-- Motor ----------------------------------------------------------------------------------------

create or replace function privado.expr_dim(p_dim text) returns text
language sql immutable set search_path = '' as $$
  select format('coalesce(%s, %L)', case p_dim
    when 'grupo'               then 'g.nombre'
    when 'asignatura'          then 'a.nombre'
    when 'departamento'        then 'd.nombre'
    when 'etapa'               then 'coalesce(re.etapa, g.etapa, c.etapa)'
    when 'cuestionario'        then 'c.codigo'
    when 'docente'             then $e$case r.docente when true then 'docente' when false then 'no_docente' end$e$
    when 'antiguedad'          then 'r.antiguedad'
    when 'departamento_equipo' then 'r.departamento_equipo'
    when 'tramo'               then 'rt.tramo'
    when 'docente_atribuido'   then 'rd.docente_id::text'
  end, '(sin dato)')
  where p_dim is not null;
$$;

-- Las métricas que llegan del cliente solo llevan tipo y código. Las claves internas
-- (conjuntos de tramos o departamentos, grupo y asignatura de una clase) solo las usan las
-- RPC de este fichero, que aplican sus propias comprobaciones.
create function privado.exigir_metrica_publica(p_metrica jsonb) returns void
language plpgsql immutable set search_path = '' as $$
declare k text;
begin
  for k in select jsonb_object_keys(coalesce(p_metrica, '{}')) loop
    if k not in ('tipo', 'codigo') then
      raise exception 'Métrica no válida: %', k;
    end if;
  end loop;
end $$;

-- Igual que en la migración 10, con «tramo» entre las claves de personal (nunca combinado).
create or replace function privado.resolver(p_filtro jsonb, p_dims text[])
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_perfil     public.usuario_perfil := permisos.exigir();
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
    when 'alumnos'  then array['cuestionario', 'etapa', 'grupo', 'asignatura']
    when 'familias' then array['etapa']
    else array['docente', 'antiguedad', 'departamento_equipo', 'departamento', 'tramo']
  end;

  for k in select jsonb_object_keys(v_filtro) loop
    if k not in ('curso', 'colectivo') and not k = any(v_particion)
       and not (v_col = 'alumnos' and k = 'etapas') then
      raise exception 'Filtro no válido para %: %', v_col, k;
    end if;
  end loop;
  foreach k in array coalesce(p_dims, '{}') loop
    if not k = any(v_particion) then
      raise exception 'Dimensión no válida para %: %', v_col, k;
    end if;
  end loop;

  if v_perfil.rol = 'coordinacion' then
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

-- Celdas y márgenes (ver las migraciones 4 y 7). Novedades:
--   * tramo: solo en el bloque del Equipo de Individuación (o sus preguntas) y solo repartido
--     por tramo, sin otras dimensiones.
--   * docente_atribuido: solo en las preguntas por asignatura y dentro de una clase (grupo y
--     asignatura) o de una asignatura del cuestionario; lo usa privado.clases.
--   * claves internas de la métrica: "tramos" y "departamentos" (conjuntos, sin dimensiones),
--     "grupo_id" y "asignatura_id" (una clase). El cliente no puede enviarlas
--     (privado.exigir_metrica_publica).
create or replace function privado.celdas(p_cuest integer[], p_dims text[], p_metrica jsonb)
returns table (k1 text, k2 text, agg1 boolean, agg2 boolean, n integer, datos jsonb)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_tipo      text := p_metrica ->> 'tipo';
  v_cod       text := p_metrica ->> 'codigo';
  v_pregunta  public.pregunta;
  v_dims      text[] := coalesce(p_dims, '{}');
  v_ndims     integer := coalesce(cardinality(p_dims), 0);
  v_asig      boolean := 'asignatura' = any(coalesce(p_dims, '{}'));
  v_dep       boolean := 'departamento' = any(coalesce(p_dims, '{}'));
  v_tramo     boolean := 'tramo' = any(coalesce(p_dims, '{}'));
  v_atrib     boolean := 'docente_atribuido' = any(coalesce(p_dims, '{}'));
  v_tramos    text[] := case when p_metrica ? 'tramos' then array(select jsonb_array_elements_text(p_metrica -> 'tramos')) end;
  v_deps      text[] := case when p_metrica ? 'departamentos' then array(select jsonb_array_elements_text(p_metrica -> 'departamentos')) end;
  v_grupo     integer := (p_metrica ->> 'grupo_id')::integer;
  v_asig_id   integer := (p_metrica ->> 'asignatura_id')::integer;
  v_dep_met   boolean := false;
  v_ei_met    boolean := false;
  v_porasig   boolean := false;
  v_from      text;
  v_where     text;
  v_n         text;
  v_datos     text;
  v_rec       boolean := false;
  v_dist_min  integer;
  v_dist_max  integer;
  v_pe        integer;
  v_po        integer;
  v_sql       text;
  e           text[];
begin
  if v_tipo is null or v_tipo not in ('personas', 'satisfaccion', 'bloque', 'pregunta', 'recomendacion', 'seleccion') then
    raise exception 'Métrica no válida: %', coalesce(v_tipo, '(vacía)');
  end if;
  if v_tipo in ('bloque', 'pregunta', 'seleccion') and v_cod is null then
    raise exception 'La métrica % necesita código', v_tipo;
  end if;
  if v_tipo in ('pregunta', 'seleccion') then
    select * into v_pregunta from public.pregunta where codigo_diccionario = v_cod;
    if not found then
      raise exception 'Pregunta no encontrada: %', v_cod;
    end if;
    if (v_tipo = 'seleccion') <> (v_pregunta.tipo = 'seleccion_multiple') then
      raise exception 'La pregunta % no es compatible con la métrica %', v_cod, v_tipo;
    end if;
  end if;
  if v_tipo = 'seleccion' and (v_asig or v_dep or v_tramo or v_atrib) then
    raise exception 'La selección múltiple no se reparte por asignatura ni por departamento';
  end if;

  -- Qué es la métrica: reuniones de departamento, Equipo de Individuación o por asignatura.
  if v_tipo = 'bloque' then
    select coalesce(bool_or(pc.por_departamento), false), coalesce(bool_or(pc.por_asignatura), false)
      into v_dep_met, v_porasig
    from public.pregunta_cuestionario pc join public.bloque b on b.id = pc.bloque_id
    where pc.cuestionario_id = any(p_cuest) and b.codigo = v_cod;
    v_ei_met := v_cod = 'equipo_individualizacion';
  elsif v_tipo = 'pregunta' then
    select coalesce(bool_or(pc.por_departamento), false), coalesce(bool_or(pc.por_asignatura), false),
           coalesce(bool_or(b.codigo = 'equipo_individualizacion'), false)
      into v_dep_met, v_porasig, v_ei_met
    from public.pregunta_cuestionario pc join public.bloque b on b.id = pc.bloque_id
    where pc.cuestionario_id = any(p_cuest) and pc.pregunta_id = v_pregunta.id;
  end if;

  -- Reuniones de departamento: aisladas del resto de respuestas de la persona.
  if v_dep_met and v_deps is null and (not v_dep or v_ndims > 1) then
    raise exception 'Las reuniones de departamento solo se consultan repartidas por departamento, sin otros filtros';
  end if;
  if v_dep_met and v_deps is not null and v_ndims > 0 then
    raise exception 'Un conjunto de departamentos no se reparte';
  end if;
  if (v_dep or v_deps is not null) and not v_dep_met then
    raise exception 'La dimensión departamento solo vale para las reuniones de departamento';
  end if;

  -- Tramo de tutoría: solo en el bloque del Equipo de Individuación y sin otras dimensiones.
  if (v_tramo or v_tramos is not null) and not v_ei_met then
    raise exception 'El tramo de tutoría solo vale para el bloque del Equipo de Individuación';
  end if;
  if (v_tramo and v_ndims > 1) or (v_tramos is not null and v_ndims > 0) then
    raise exception 'El tramo de tutoría no se combina con otros filtros';
  end if;

  -- Atribución a un docente: dentro de una asignatura, en preguntas por asignatura.
  if (v_atrib or v_grupo is not null or v_asig_id is not null)
     and (not v_porasig or v_tipo not in ('bloque', 'pregunta')) then
    raise exception 'La atribución a un docente solo vale para las preguntas por asignatura';
  end if;
  if v_atrib and (v_ndims > 1 or v_asig_id is null) then
    raise exception 'La atribución a un docente se consulta dentro de una asignatura, sin otras dimensiones';
  end if;

  if v_tipo = 'seleccion' then
    v_from := 'privado.respuesta_opcion o
      join privado.respuesta r on r.id = o.respuesta_id
      join public.cuestionario c on c.id = r.cuestionario_id
      left join public.grupo g on g.id = r.grupo_id
      left join public.asignatura a on false
      left join public.departamento d on false';
    v_where := 'r.cuestionario_id = any($1) and o.pregunta_id = $3';
    v_n := 'count(distinct r.id)';
    select format('jsonb_build_object(%L, jsonb_build_array(%s))', 'opciones',
             string_agg(format(
               'jsonb_build_object(%L, %L, %L, count(distinct r.id) filter (where o.opcion_id = %s), %L, 100.0 * count(distinct r.id) filter (where o.opcion_id = %s) / nullif(count(distinct r.id), 0))',
               'codigo', op.codigo, 'n', op.id, 'pct', op.id), ', ' order by op.id))
      into v_datos
    from public.opcion op where op.pregunta_id = v_pregunta.id;
    v_datos := coalesce(v_datos, '''{}''::jsonb');

  elsif v_tipo = 'personas' and not v_asig then
    v_from := 'privado.respuesta r
      join public.cuestionario c on c.id = r.cuestionario_id
      left join public.grupo g on g.id = r.grupo_id
      left join public.asignatura a on false
      left join public.departamento d on false';
    v_where := 'r.cuestionario_id = any($1) and (
        exists (select 1 from privado.respuesta_item vi where vi.respuesta_id = r.id and vi.valor is not null)
        or exists (select 1 from privado.respuesta_opcion vo where vo.respuesta_id = r.id))';
    v_n := 'count(distinct r.id)';
    v_datos := '''{}''::jsonb';

  else
    v_from := 'privado.respuesta_item i
      join privado.respuesta r on r.id = i.respuesta_id
      join public.cuestionario c on c.id = r.cuestionario_id
      left join public.grupo g on g.id = r.grupo_id
      left join public.asignatura a on a.id = i.asignatura_id
      left join public.departamento d on d.id = i.departamento_id
      join public.pregunta p on p.id = i.pregunta_id
      join public.pregunta_cuestionario pc on pc.cuestionario_id = r.cuestionario_id and pc.pregunta_id = i.pregunta_id
      join public.bloque b on b.id = pc.bloque_id'
      || case when v_tramo or v_tramos is not null
              then ' left join privado.respuesta_tramo rt on rt.respuesta_id = r.id' else '' end
      || case when v_atrib
              then ' left join privado.respuesta_docente rd on rd.respuesta_id = r.id and rd.asignatura_id = i.asignatura_id' else '' end;
    v_where := 'r.cuestionario_id = any($1)' || case v_tipo
      when 'personas'      then ' and i.valor is not null'
      when 'satisfaccion'  then ' and p.tipo = ''escala'' and p.escala_min = 1 and p.escala_max = 6 and b.entra_en_media'
      when 'bloque'        then ' and p.tipo = ''escala'' and b.codigo = $2'
      when 'pregunta'      then ' and i.pregunta_id = $3'
      when 'recomendacion' then ' and p.tipo = ''recomendacion'''
    end;
    v_where := v_where || case when v_dep_met then ' and pc.por_departamento' else ' and not pc.por_departamento' end;
    if v_asig then
      v_where := v_where || ' and i.asignatura_id is not null';
    end if;
    if v_tramos is not null then
      v_where := v_where || ' and rt.tramo = any($4)';
    end if;
    if v_deps is not null then
      v_where := v_where || ' and d.nombre = any($5)';
    end if;
    if v_grupo is not null then
      v_where := v_where || ' and r.grupo_id = $6';
    end if;
    if v_asig_id is not null then
      v_where := v_where || ' and i.asignatura_id = $7';
    end if;

    v_n := case when v_tipo in ('pregunta', 'recomendacion') then 'count(i.valor)'
                else 'count(distinct r.id) filter (where i.valor is not null)' end;

    if v_tipo = 'personas' then
      v_datos := '''{}''::jsonb';
    else
      v_datos := 'jsonb_build_object(
        ''n_personas'', count(distinct r.id) filter (where i.valor is not null),
        ''n_valoraciones'', count(i.valor),
        ''media'', avg(i.valor),
        ''ns_nc'', count(*) filter (where i.ns_nc))';
    end if;

    v_rec := v_tipo = 'recomendacion' or (v_tipo = 'pregunta' and v_pregunta.tipo = 'recomendacion');
    if v_tipo = 'recomendacion' then
      v_dist_min := 0; v_dist_max := 10;
    elsif v_tipo = 'pregunta' then
      v_dist_min := v_pregunta.escala_min; v_dist_max := v_pregunta.escala_max;
    end if;

    if v_dist_min is not null then
      select v_datos || format(' || jsonb_build_object(%L, jsonb_build_object(%s))', 'distribucion',
               string_agg(format('%L, count(*) filter (where i.valor = %s)', v::text, v), ', ' order by v))
        into v_datos
      from generate_series(v_dist_min, v_dist_max) v;
    end if;

    if v_rec then
      v_datos := v_datos || ' || jsonb_build_object(
        ''promotores_pct'', 100.0 * count(*) filter (where i.valor >= 9) / nullif(count(i.valor), 0),
        ''neutros_pct'', 100.0 * count(*) filter (where i.valor in (7, 8)) / nullif(count(i.valor), 0),
        ''detractores_pct'', 100.0 * count(*) filter (where i.valor <= 6) / nullif(count(i.valor), 0),
        ''nps'', 100.0 * (count(*) filter (where i.valor >= 9) - count(*) filter (where i.valor <= 6)) / nullif(count(i.valor), 0))';
    end if;
  end if;

  e := array[privado.expr_dim(v_dims[1]), privado.expr_dim(v_dims[2])];
  v_pe := array_position(v_dims, 'etapa');

  if v_pe is null then
    v_sql := format(
      'select %s, %s, %s, %s, (%s)::integer, %s from %s where %s %s',
      coalesce(e[1], 'null::text'),
      coalesce(e[2], 'null::text'),
      case when e[1] is null then 'true' else format('grouping(%s) = 1', e[1]) end,
      case when e[2] is null then 'true' else format('grouping(%s) = 1', e[2]) end,
      v_n, v_datos, v_from, v_where,
      case v_ndims
        when 0 then ''
        when 1 then format('group by grouping sets ((%s), ())', e[1])
        else format('group by grouping sets ((%1$s, %2$s), (%1$s), (%2$s), ())', e[1], e[2])
      end);
  else
    v_po := case when v_ndims = 2 then 3 - v_pe end;
    v_sql := format(
      'select %s, %s, %s, %s, (%s)::integer, %s from %s left join privado.respuesta_etapa re on re.respuesta_id = r.id where %s %s',
      case when v_pe = 1 then e[1] else coalesce(e[1], 'null::text') end,
      case when v_pe = 2 then e[2] else coalesce(e[2], 'null::text') end,
      case when v_pe = 1 then 'false' when e[1] is null then 'true' else format('grouping(%s) = 1', e[1]) end,
      case when v_pe = 2 then 'false' when e[2] is null then 'true' else format('grouping(%s) = 1', e[2]) end,
      v_n, v_datos, v_from, v_where,
      case when v_po is null then format('group by %s', e[v_pe])
           else format('group by grouping sets ((%1$s, %2$s), (%1$s))', e[v_pe], e[v_po]) end)
    || ' union all ' ||
    format(
      'select %s, %s, %s, %s, (%s)::integer, %s from %s where %s %s',
      case when v_pe = 1 then 'null::text' else coalesce(e[1], 'null::text') end,
      case when v_pe = 2 then 'null::text' else coalesce(e[2], 'null::text') end,
      case when v_pe = 1 then 'true' when e[1] is null then 'true' else format('grouping(%s) = 1', e[1]) end,
      case when v_pe = 2 then 'true' when e[2] is null then 'true' else format('grouping(%s) = 1', e[2]) end,
      v_n, v_datos, v_from, v_where,
      case when v_po is null then '' else format('group by grouping sets ((%s), ())', e[v_po]) end);
  end if;

  return query execute format('select * from (%s) t order by 1 nulls first, 2 nulls first', v_sql)
  using p_cuest, v_cod, v_pregunta.id, v_tramos, v_deps, v_grupo, v_asig_id;
end $$;

-- Resultado de un conjunto de partes de una dimensión (tramos o departamentos de un mismo
-- responsable), con el mínimo de 5. Si alguna de esas partes se ve por separado y otra no, el
-- conjunto se oculta: restando la visible se deduciría la oculta.
create function privado.conjunto(p_cuest integer[], p_dim text, p_valores text[], p_metrica jsonb)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  a_k1 text[]; a_k2 text[]; a_g1 boolean[]; a_g2 boolean[]; a_n integer[]; a_d jsonb[];
  v_mot      text[];
  v_vis      integer := 0;
  v_ocu      integer := 0;
  v_n        integer;
  v_datos    jsonb;
  i integer;
begin
  if p_dim not in ('tramo', 'departamento') then
    raise exception 'Dimensión no válida para un conjunto: %', p_dim;
  end if;
  select array_agg(x.k1), array_agg(x.k2), array_agg(x.agg1), array_agg(x.agg2), array_agg(x.n), array_agg(x.datos)
    into a_k1, a_k2, a_g1, a_g2, a_n, a_d
  from privado.celdas(p_cuest, array[p_dim], p_metrica) x;
  v_mot := privado.suprimir(a_k1, a_k2, a_g1, a_g2, a_n);
  for i in 1 .. coalesce(cardinality(a_n), 0) loop
    continue when a_g1[i] or not a_k1[i] = any(p_valores);
    if v_mot[i] is null then v_vis := v_vis + 1; else v_ocu := v_ocu + 1; end if;
  end loop;

  if v_vis + v_ocu = 0 then
    return privado.fila('{}', 'sin_datos', null, null);
  end if;
  if v_vis > 0 and v_ocu > 0 then
    return privado.fila('{}', 'complementaria', null, null);
  end if;

  select x.n, x.datos into v_n, v_datos
  from privado.celdas(p_cuest, '{}', p_metrica || jsonb_build_object(
         case p_dim when 'tramo' then 'tramos' else 'departamentos' end, to_jsonb(p_valores))) x;
  return privado.fila('{}', case when coalesce(v_n, 0) < 5 then 'menos_de_5' end, v_n, v_datos);
end $$;

-- Resultados públicos: igual que en la migración 5, sin claves internas en la métrica.
create or replace function public.resultados(p_filtro jsonb, p_metrica jsonb, p_dimensiones text[] default '{}')
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_res     jsonb;
  v_dims    text[];
  v_fijos   jsonb;
  v_cuest   integer[];
  a_k1 text[]; a_k2 text[]; a_g1 boolean[]; a_g2 boolean[]; a_n integer[]; a_d jsonb[];
  v_mot     text[];
  v_total   jsonb;
  v_partes  jsonb := '[]';
  v_clave   jsonb;
  v_ok      boolean;
  v_es_total boolean;
  v_k       text;
  v_agg     boolean;
  i integer; d integer;
begin
  perform privado.exigir_metrica_publica(p_metrica);
  v_res := privado.resolver(p_filtro, p_dimensiones);
  v_dims := array(select jsonb_array_elements_text(v_res -> 'dims'));
  v_fijos := v_res -> 'fijos';
  v_cuest := array(select jsonb_array_elements_text(v_res -> 'cuestionarios')::integer);

  select array_agg(c.k1), array_agg(c.k2), array_agg(c.agg1), array_agg(c.agg2), array_agg(c.n), array_agg(c.datos)
    into a_k1, a_k2, a_g1, a_g2, a_n, a_d
  from privado.celdas(v_cuest, v_dims, p_metrica) c;

  v_mot := privado.suprimir(a_k1, a_k2, a_g1, a_g2, a_n);

  for i in 1 .. coalesce(cardinality(a_n), 0) loop
    v_ok := true;
    v_es_total := true;
    v_clave := v_fijos;
    for d in 1 .. cardinality(v_dims) loop
      v_k := case d when 1 then a_k1[i] else a_k2[i] end;
      v_agg := case d when 1 then a_g1[i] else a_g2[i] end;
      if v_fijos ? v_dims[d] then
        v_ok := v_ok and not v_agg and v_k = v_fijos ->> v_dims[d];
      elsif not v_agg then
        v_es_total := false;
        v_clave := v_clave || jsonb_build_object(v_dims[d], v_k);
      end if;
    end loop;
    continue when not v_ok;

    if v_es_total then
      v_total := privado.fila(v_clave, v_mot[i], a_n[i], a_d[i]);
    else
      v_partes := v_partes || privado.fila(v_clave, v_mot[i], a_n[i], a_d[i]);
    end if;
  end loop;

  return jsonb_build_object(
    'metrica', p_metrica,
    'dimensiones', v_res -> 'salida',
    'total', coalesce(v_total, privado.fila(v_fijos, 'sin_datos', null, null)),
    'partes', v_partes
  );
end $$;

-- 4. Clases de uno o varios docentes ----------------------------------------------------------
--
-- Una fila por docente y clase (grupo y asignatura de la encuesta) con su estado en la tabla
-- asignatura por grupo de su cuestionario (mínimo de 5 y complementaria):
--   propia      · un solo docente en la clase;
--   compartida  · varios docentes y ninguna atribución: el resultado es el de la clase;
--   atribuida   · varios docentes con atribución por nombre: el subconjunto de alumnos que
--                 lo nombraron, con la complementaria entre los docentes de la clase y los
--                 alumnos sin atribuir. Si la clase está oculta, todos sus subconjuntos lo están.
-- Además, las asignaturas atribuidas sin asignación por grupo (las optativas) van por
-- cuestionario: grupo nulo y complementaria entre docentes dentro de la asignatura.
create function privado.clases(p_curso smallint, p_docentes integer[], p_metrica jsonb, p_etapa text default null)
returns table (docente_id integer, cuestionario text, etapa text, grupo text, asignatura text,
               tipo text, docentes_clase integer, motivo text, n integer, datos jsonb)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_c        record;
  v_a        record;
  a_k1 text[]; a_k2 text[]; a_g1 boolean[]; a_g2 boolean[]; a_n integer[]; a_d jsonb[];
  v_mot      text[];
  b_k1 text[]; b_g1 boolean[]; b_n integer[]; b_d jsonb[];
  b_mot      text[];
  v_gid      integer;
  v_aid      integer;
  v_doc      integer[];
  v_mot_t    text;
  v_d        integer;
  i integer; j integer;
begin
  for v_c in
    select c.id, c.codigo, c.etapa from public.cuestionario c
    where c.curso_id = p_curso and c.colectivo = 'alumnos' and (p_etapa is null or c.etapa = p_etapa)
      and (exists (select 1 from public.asignacion_docente ad join public.grupo g on g.id = ad.grupo_id
                   where ad.curso_id = p_curso and ad.docente_id = any(p_docentes) and g.etapa = c.etapa
                     and exists (select 1 from privado.respuesta r where r.cuestionario_id = c.id and r.grupo_id = g.id))
           or exists (select 1 from privado.respuesta_docente rd join privado.respuesta r on r.id = rd.respuesta_id
                      where r.cuestionario_id = c.id and rd.docente_id = any(p_docentes)))
    order by c.id
  loop
    select array_agg(x.k1), array_agg(x.k2), array_agg(x.agg1), array_agg(x.agg2), array_agg(x.n), array_agg(x.datos)
      into a_k1, a_k2, a_g1, a_g2, a_n, a_d
    from privado.celdas(array[v_c.id], array['grupo', 'asignatura'], p_metrica) x;
    v_mot := privado.suprimir(a_k1, a_k2, a_g1, a_g2, a_n);

    for i in 1 .. coalesce(cardinality(a_n), 0) loop
      continue when a_g1[i] or a_g2[i];
      select g.id into v_gid from public.grupo g where g.curso_id = p_curso and g.nombre = a_k1[i];
      select a.id into v_aid from public.asignatura a where a.curso_id = p_curso and a.nombre = a_k2[i];
      select array_agg(ad.docente_id order by ad.docente_id) into v_doc
      from public.asignacion_docente ad
      where ad.curso_id = p_curso and ad.grupo_id = v_gid and ad.asignatura_id = v_aid;
      continue when v_doc is null or not (v_doc && p_docentes);

      if cardinality(v_doc) = 1 then
        return query select v_doc[1], v_c.codigo, v_c.etapa, a_k1[i], a_k2[i], 'propia'::text, 1, v_mot[i], a_n[i], a_d[i];
        continue;
      end if;

      if not exists (select 1 from privado.respuesta_docente rd join privado.respuesta r on r.id = rd.respuesta_id
                     where r.cuestionario_id = v_c.id and r.grupo_id = v_gid and rd.asignatura_id = v_aid) then
        return query select x, v_c.codigo, v_c.etapa, a_k1[i], a_k2[i], 'compartida'::text, cardinality(v_doc), v_mot[i], a_n[i], a_d[i]
                     from unnest(v_doc) x where x = any(p_docentes);
        continue;
      end if;

      select array_agg(y.k1), array_agg(y.agg1), array_agg(y.n), array_agg(y.datos)
        into b_k1, b_g1, b_n, b_d
      from privado.celdas(array[v_c.id], array['docente_atribuido'],
             p_metrica || jsonb_build_object('grupo_id', v_gid, 'asignatura_id', v_aid)) y;
      b_mot := privado.suprimir(b_k1, array_fill(null::text, array[cardinality(b_n)]), b_g1,
                                array_fill(true, array[cardinality(b_n)]), b_n);
      foreach v_d in array v_doc loop
        continue when not v_d = any(p_docentes);
        j := null;
        for k in 1 .. cardinality(b_n) loop
          if not b_g1[k] and b_k1[k] = v_d::text then j := k; end if;
        end loop;
        if j is null then
          return query select v_d, v_c.codigo, v_c.etapa, a_k1[i], a_k2[i], 'atribuida'::text, cardinality(v_doc), 'sin_datos'::text, null::integer, null::jsonb;
        else
          return query select v_d, v_c.codigo, v_c.etapa, a_k1[i], a_k2[i], 'atribuida'::text, cardinality(v_doc),
                              case when v_mot[i] is not null then coalesce(b_mot[j], 'complementaria') else b_mot[j] end, b_n[j], b_d[j];
        end if;
      end loop;
    end loop;

    -- Asignaturas atribuidas sin asignación por grupo (optativas): por cuestionario.
    for v_a in
      select distinct rd.asignatura_id, a.nombre
      from privado.respuesta_docente rd
      join privado.respuesta r on r.id = rd.respuesta_id
      join public.asignatura a on a.id = rd.asignatura_id
      where r.cuestionario_id = v_c.id and rd.docente_id = any(p_docentes)
        and not exists (select 1 from public.asignacion_docente ad join public.grupo g on g.id = ad.grupo_id
                        where ad.curso_id = p_curso and ad.asignatura_id = rd.asignatura_id and g.etapa = v_c.etapa)
    loop
      -- Estado de la asignatura entera en la tabla del cuestionario (margen de la columna).
      v_mot_t := null;
      for i in 1 .. coalesce(cardinality(a_n), 0) loop
        if a_g1[i] and not a_g2[i] and a_k2[i] = v_a.nombre then v_mot_t := v_mot[i]; end if;
      end loop;
      select array_agg(y.k1), array_agg(y.agg1), array_agg(y.n), array_agg(y.datos)
        into b_k1, b_g1, b_n, b_d
      from privado.celdas(array[v_c.id], array['docente_atribuido'],
             p_metrica || jsonb_build_object('asignatura_id', v_a.asignatura_id)) y;
      b_mot := privado.suprimir(b_k1, array_fill(null::text, array[cardinality(b_n)]), b_g1,
                                array_fill(true, array[cardinality(b_n)]), b_n);
      for j in 1 .. cardinality(b_n) loop
        continue when b_g1[j];
        continue when b_k1[j] = '(sin dato)';
        continue when not b_k1[j]::integer = any(p_docentes);
        return query select b_k1[j]::integer, v_c.codigo, v_c.etapa, null::text, v_a.nombre, 'atribuida'::text,
                            (select count(distinct rd2.docente_id)::integer from privado.respuesta_docente rd2
                               join privado.respuesta r2 on r2.id = rd2.respuesta_id
                              where r2.cuestionario_id = v_c.id and rd2.asignatura_id = v_a.asignatura_id),
                            case when v_mot_t is not null then coalesce(b_mot[j], 'complementaria') else b_mot[j] end,
                            b_n[j], b_d[j];
      end loop;
    end loop;
  end loop;
end $$;

-- Profesores: con asignación o con respuestas atribuidas en el curso.
create or replace function public.listar_profesores(p_curso text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_perfil public.usuario_perfil := permisos.exigir();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', pr.id, 'nombre', pr.nombre, 'apellidos', pr.apellidos,
             'departamento', dep.nombre, 'situacion', pr.situacion)
           order by pr.apellidos, pr.nombre)
    from public.persona_responsable pr
    left join public.departamento dep on dep.id = pr.departamento_id
    where exists (
        select 1 from public.asignacion_docente ad
        join public.curso cu on cu.id = ad.curso_id
        join public.grupo g on g.id = ad.grupo_id
        where ad.docente_id = pr.id and cu.nombre = p_curso
          and (v_perfil.rol <> 'coordinacion' or g.etapa = v_perfil.etapa))
      or exists (
        select 1 from privado.respuesta_docente rd
        join privado.respuesta r on r.id = rd.respuesta_id
        join public.cuestionario c on c.id = r.cuestionario_id
        join public.curso cu on cu.id = c.curso_id
        where rd.docente_id = pr.id and cu.nombre = p_curso
          and (v_perfil.rol <> 'coordinacion' or c.etapa = v_perfil.etapa))
  ), '[]');
end $$;

-- Resultados de un profesor: «Sus clases» (propias y atribuidas) y «Valoraciones
-- compartidas». La media global sale solo de las suyas visibles (§5.12).
create or replace function public.resultados_profesor(
  p_curso text,
  p_docente integer,
  p_metrica jsonb default '{"tipo": "bloque", "codigo": "profesorado"}'
)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_perfil     public.usuario_perfil := permisos.exigir();
  v_curso      smallint;
  v_docente    public.persona_responsable;
  v_f          record;
  v_celdas     jsonb := '[]';
  v_suma       numeric := 0;
  v_nval       integer := 0;
  v_nper       integer := 0;
  v_visibles   integer := 0;
  v_excluidas  integer := 0;
  v_compartidas integer := 0;
  v_etapas     text[] := '{}';
  v_comp       jsonb := '{}';
  v_e          text;
  v_cmp        jsonb;
  v_etapa      text;
begin
  perform privado.exigir_metrica_publica(p_metrica);
  select id into v_curso from public.curso where nombre = p_curso;
  select * into v_docente from public.persona_responsable where id = p_docente;
  if v_curso is null or v_docente.id is null then
    raise exception 'Profesor o curso no encontrado' using errcode = 'P0002';
  end if;

  if v_perfil.rol = 'coordinacion' then
    v_etapa := v_perfil.etapa;
    if not exists (
      select 1 from public.asignacion_docente ad join public.grupo g on g.id = ad.grupo_id
      where ad.docente_id = p_docente and ad.curso_id = v_curso and g.etapa = v_etapa
    ) and not exists (
      select 1 from privado.respuesta_docente rd join privado.respuesta r on r.id = rd.respuesta_id
      join public.cuestionario c on c.id = r.cuestionario_id
      where rd.docente_id = p_docente and c.curso_id = v_curso and c.etapa = v_etapa
    ) then
      raise exception 'Sin acceso a este profesor' using errcode = '42501';
    end if;
  end if;

  for v_f in select * from privado.clases(v_curso, array[p_docente], p_metrica, v_etapa) loop
    v_celdas := v_celdas || (privado.fila(
      jsonb_build_object('cuestionario', v_f.cuestionario, 'grupo', v_f.grupo, 'asignatura', v_f.asignatura),
      v_f.motivo, v_f.n, v_f.datos)
      || jsonb_build_object('etapa', v_f.etapa, 'tipo', v_f.tipo, 'docentes_clase', v_f.docentes_clase));

    if v_f.tipo = 'compartida' then
      v_compartidas := v_compartidas + 1;
    elsif v_f.motivo is null then
      v_visibles := v_visibles + 1;
      v_nper := v_nper + coalesce((v_f.datos ->> 'n_personas')::integer, v_f.n);
      v_nval := v_nval + coalesce((v_f.datos ->> 'n_valoraciones')::integer, 0);
      v_suma := v_suma + coalesce((v_f.datos ->> 'media')::numeric * (v_f.datos ->> 'n_valoraciones')::integer, 0);
    else
      v_excluidas := v_excluidas + 1;
    end if;
    if v_f.motivo is null and not v_f.etapa = any(v_etapas) then
      v_etapas := v_etapas || v_f.etapa;
    end if;
  end loop;

  foreach v_e in array v_etapas loop
    select privado.fila(jsonb_build_object('etapa', v_e), case when x.n < 5 then 'menos_de_5' end, x.n, x.datos)
      into v_cmp
    from privado.celdas(
      array(select c.id from public.cuestionario c where c.curso_id = v_curso and c.colectivo = 'alumnos' and c.etapa = v_e),
      '{}', p_metrica) x;
    v_comp := v_comp || jsonb_build_object(v_e, v_cmp);
  end loop;
  select privado.fila('{}', case when x.n < 5 then 'menos_de_5' end, x.n, x.datos)
    into v_cmp
  from privado.celdas(
    array(select c.id from public.cuestionario c where c.curso_id = v_curso and c.colectivo = 'alumnos'),
    '{}', p_metrica) x;
  v_comp := v_comp || jsonb_build_object('colegio', v_cmp);

  return jsonb_build_object(
    'docente', jsonb_build_object('id', v_docente.id, 'nombre', v_docente.nombre, 'apellidos', v_docente.apellidos,
                                  'situacion', v_docente.situacion),
    'metrica', p_metrica,
    'celdas', v_celdas,
    'global', case when v_visibles = 0
      then jsonb_build_object('suprimido', true, 'motivo', 'sin_combinaciones_visibles')
      else jsonb_build_object('suprimido', false,
             'combinaciones', v_visibles,
             'n_personas_por_asignatura', v_nper,
             'n_valoraciones', v_nval,
             'media', case when v_nval > 0 then v_suma / v_nval end)
    end,
    'combinaciones_excluidas', v_excluidas,
    'compartidas', v_compartidas,
    'comparacion', v_comp
  );
end $$;

-- Media de los profesores de un departamento oficial según los alumnos: solo sus clases
-- propias y atribuidas visibles (las compartidas no entran, como en la media del profesor).
create or replace function public.media_departamento_alumnos(p_curso text, p_departamento text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_curso      smallint;
  v_docs       integer[];
  v_f          record;
  v_suma       numeric := 0;
  v_nval       integer := 0;
  v_visibles   integer := 0;
  v_excluidas  integer := 0;
begin
  perform permisos.exigir();
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a los informes de responsables' using errcode = '42501';
  end if;
  select id into v_curso from public.curso where nombre = p_curso;

  select array_agg(distinct pr.id) into v_docs
  from public.persona_responsable pr
  join public.departamento d on d.id = pr.departamento_id
  where d.curso_id = v_curso and d.nombre = p_departamento
    and (exists (select 1 from public.asignacion_docente ad where ad.docente_id = pr.id and ad.curso_id = v_curso)
         or exists (select 1 from privado.respuesta_docente rd where rd.docente_id = pr.id));

  if v_docs is null then
    return jsonb_build_object('profesores', 0,
      'global', jsonb_build_object('suprimido', true, 'motivo', 'sin_asignacion'), 'combinaciones_excluidas', 0);
  end if;

  for v_f in select * from privado.clases(v_curso, v_docs, '{"tipo": "bloque", "codigo": "profesorado"}') where tipo <> 'compartida' loop
    if v_f.motivo is null then
      v_visibles := v_visibles + 1;
      v_nval := v_nval + (v_f.datos ->> 'n_valoraciones')::integer;
      v_suma := v_suma + (v_f.datos ->> 'media')::numeric * (v_f.datos ->> 'n_valoraciones')::integer;
    else
      v_excluidas := v_excluidas + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'profesores', cardinality(v_docs),
    'global', case when v_visibles = 0 then jsonb_build_object('suprimido', true, 'motivo', 'sin_combinaciones_visibles')
                   else jsonb_build_object('suprimido', false, 'combinaciones', v_visibles, 'n_valoraciones', v_nval,
                                           'media', v_suma / nullif(v_nval, 0)) end,
    'combinaciones_excluidas', v_excluidas);
end $$;

-- 5. Responsables -------------------------------------------------------------------------------

-- Resultado de un bloque de personal (total y preguntas) sobre una parte o un conjunto de
-- partes de una dimensión aislada (departamento o tramo).
create function privado.informe_partes(p_curso text, p_bloque text, p_dim text, p_valores text[])
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_filtro  jsonb := jsonb_build_object('curso', p_curso, 'colectivo', 'personal');
  v_cuest   integer[] := array(select jsonb_array_elements_text(privado.resolver(v_filtro, '{}') -> 'cuestionarios')::integer);
  v_total   jsonb;
  v_preg    jsonb := '[]';
  v_p       record;
begin
  if cardinality(p_valores) = 1 then
    v_filtro := v_filtro || jsonb_build_object(p_dim, p_valores[1]);
    v_total := public.resultados(v_filtro, jsonb_build_object('tipo', 'bloque', 'codigo', p_bloque)) -> 'total';
    if not (v_total ->> 'suprimido')::boolean then
      v_preg := public.detalle_preguntas(v_filtro, p_bloque);
    end if;
  else
    v_total := privado.conjunto(v_cuest, p_dim, p_valores, jsonb_build_object('tipo', 'bloque', 'codigo', p_bloque));
    if not (v_total ->> 'suprimido')::boolean then
      for v_p in
        select p.codigo_diccionario, p.texto_es
        from public.pregunta_cuestionario pc
        join public.bloque b on b.id = pc.bloque_id
        join public.pregunta p on p.id = pc.pregunta_id
        where pc.cuestionario_id = any(v_cuest) and b.codigo = p_bloque
        group by p.codigo_diccionario, p.texto_es
        order by min(pc.orden), p.codigo_diccionario
      loop
        v_preg := v_preg || jsonb_build_object('codigo', v_p.codigo_diccionario, 'texto', v_p.texto_es,
          'resultado', jsonb_build_object('total',
            privado.conjunto(v_cuest, p_dim, p_valores, jsonb_build_object('tipo', 'pregunta', 'codigo', v_p.codigo_diccionario))));
      end loop;
    end if;
  end if;
  return jsonb_build_object('total', v_total, 'preguntas', v_preg);
end $$;

-- Jefes de departamento del curso, con sus departamentos oficiales.
create function public.listar_jefes(p_curso text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform permisos.exigir();
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a los informes de responsables' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(j order by j ->> 'primero', j ->> 'apellidos')
    from (
      select jsonb_build_object('id', pr.id, 'nombre', pr.nombre, 'apellidos', pr.apellidos,
               'departamentos', jsonb_agg(ca.ambito order by ca.ambito), 'primero', min(ca.ambito)) as j
      from public.cargo ca
      join public.curso cu on cu.id = ca.curso_id
      join public.persona_responsable pr on pr.id = ca.persona_id
      where cu.nombre = p_curso and ca.tipo = 'jefe_departamento'
      group by pr.id
    ) x
  ), '[]');
end $$;

-- Informe de un jefe de departamento: reuniones (por unidad de la encuesta, o juntas si cada
-- una queda oculta por separado y el conjunto se ve) y media de alumnos de cada departamento.
create or replace function public.informe_jefe_departamento(p_curso text, p_persona integer, p_registrar boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_curso    smallint;
  v_pr       public.persona_responsable;
  v_deps     text[];
  v_unidades text[];
  v_ocultas  boolean := true;
  v_u        text;
  v_sec      jsonb := '[]';
  v_inf      jsonb;
  v_alu      jsonb := '[]';
  v_d        text;
  v_conjunto jsonb;
begin
  perform permisos.exigir();
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a los informes de responsables' using errcode = '42501';
  end if;
  select id into v_curso from public.curso where nombre = p_curso;
  select * into v_pr from public.persona_responsable where id = p_persona;
  select array_agg(ca.ambito order by ca.ambito) into v_deps
  from public.cargo ca where ca.persona_id = p_persona and ca.curso_id = v_curso and ca.tipo = 'jefe_departamento';
  if v_pr.id is null or v_deps is null then
    raise exception 'Jefe de departamento no encontrado' using errcode = 'P0002';
  end if;

  -- Unidades de la encuesta que corresponden a sus departamentos (con equivalencia o por nombre).
  select array_agg(distinct u.nombre order by u.nombre) into v_unidades
  from public.departamento o
  join lateral (
    select de.nombre from public.departamento_equivalencia eq
    join public.departamento de on de.id = eq.departamento_encuesta_id
    where eq.departamento_id = o.id
    union
    select o.nombre where exists (select 1 from privado.respuesta_item i where i.departamento_id = o.id)
  ) u on true
  where o.curso_id = v_curso and o.nombre = any(v_deps);

  if v_unidades is not null and cardinality(v_unidades) > 1 then
    foreach v_u in array v_unidades loop
      v_inf := privado.informe_partes(p_curso, 'reuniones_departamento', 'departamento', array[v_u]);
      v_ocultas := v_ocultas and (v_inf -> 'total' ->> 'suprimido')::boolean;
      v_sec := v_sec || (jsonb_build_object('unidades', jsonb_build_array(v_u), 'conjunto', false) || v_inf);
    end loop;
    if v_ocultas then
      v_conjunto := privado.informe_partes(p_curso, 'reuniones_departamento', 'departamento', v_unidades);
      if not (v_conjunto -> 'total' ->> 'suprimido')::boolean then
        v_sec := jsonb_build_array(jsonb_build_object('unidades', to_jsonb(v_unidades), 'conjunto', true) || v_conjunto);
      end if;
    end if;
  elsif v_unidades is not null then
    v_sec := jsonb_build_array(jsonb_build_object('unidades', to_jsonb(v_unidades), 'conjunto', false)
             || privado.informe_partes(p_curso, 'reuniones_departamento', 'departamento', v_unidades));
  end if;

  foreach v_d in array v_deps loop
    v_alu := v_alu || jsonb_build_object('departamento', v_d, 'media', public.media_departamento_alumnos(p_curso, v_d));
  end loop;

  if p_registrar then
    perform privado.registrar('informe_responsable', jsonb_build_object('curso', p_curso, 'tipo', 'jefe_departamento',
      'ambito', array_to_string(v_deps, ', ')));
  end if;

  return jsonb_build_object(
    'persona', jsonb_build_object('id', v_pr.id, 'nombre', v_pr.nombre, 'apellidos', v_pr.apellidos),
    'departamentos', to_jsonb(v_deps),
    'reuniones', v_sec,
    'alumnos', v_alu);
end $$;

-- Equipo de Individuación: grupos de tramos con sus responsables. Cada tramo visible va solo;
-- los tramos ocultos se juntan en un resultado compartido si juntos llegan al mínimo.
create function public.listar_equipo(p_curso text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_r       jsonb;
  v_vis     text[] := '{}';
  v_ocu     text[] := '{}';
  v_p       jsonb;
  v_grupos  jsonb := '[]';
  v_t       text;
begin
  perform permisos.exigir();
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a los informes de responsables' using errcode = '42501';
  end if;
  v_r := public.resultados(jsonb_build_object('curso', p_curso, 'colectivo', 'personal'),
                           '{"tipo": "bloque", "codigo": "equipo_individualizacion"}', '{tramo}');
  for v_p in select * from jsonb_array_elements(v_r -> 'partes') loop
    continue when v_p -> 'clave' ->> 'tramo' = '(sin dato)';
    if (v_p ->> 'suprimido')::boolean then v_ocu := v_ocu || (v_p -> 'clave' ->> 'tramo');
    else v_vis := v_vis || (v_p -> 'clave' ->> 'tramo'); end if;
  end loop;

  foreach v_t in array v_vis loop
    v_grupos := v_grupos || jsonb_build_object('tramos', jsonb_build_array(v_t));
  end loop;
  if cardinality(v_ocu) > 0 then
    v_grupos := v_grupos || jsonb_build_object('tramos', to_jsonb(v_ocu));
  end if;

  return coalesce((
    select jsonb_agg(g || jsonb_build_object('responsables', coalesce((
             select jsonb_agg(jsonb_build_object('nombre', pr.nombre, 'apellidos', pr.apellidos, 'tramo', ca.ambito)
                              order by array_position(array['infantil', 'y1_y5', 'y6_y9', 'y10_y12'], ca.ambito))
             from public.cargo ca
             join public.curso cu on cu.id = ca.curso_id
             join public.persona_responsable pr on pr.id = ca.persona_id
             where cu.nombre = p_curso and ca.tipo = 'jefe_equipo'
               and ca.ambito in (select jsonb_array_elements_text(g -> 'tramos'))), '[]'))
           order by array_position(array['infantil', 'y1_y5', 'y6_y9', 'y10_y12'], g -> 'tramos' ->> 0))
    from jsonb_array_elements(v_grupos) g
  ), '[]');
end $$;

-- Informe del Equipo de Individuación para uno o varios tramos (varios: resultado compartido).
create function public.informe_equipo(p_curso text, p_tramos text[], p_registrar boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_inf jsonb;
begin
  perform permisos.exigir();
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a los informes de responsables' using errcode = '42501';
  end if;
  if p_tramos is null or cardinality(p_tramos) = 0
     or not p_tramos <@ array['infantil', 'y1_y5', 'y6_y9', 'y10_y12'] then
    raise exception 'Tramos no válidos';
  end if;
  v_inf := privado.informe_partes(p_curso, 'equipo_individualizacion', 'tramo', p_tramos);
  if p_registrar then
    perform privado.registrar('informe_responsable', jsonb_build_object('curso', p_curso, 'tipo', 'equipo_individuacion',
      'ambito', array_to_string(p_tramos, ', ')));
  end if;
  return jsonb_build_object('tramos', to_jsonb(p_tramos)) || v_inf;
end $$;

do $$
declare f text;
begin
  foreach f in array array['public.listar_jefes(text)', 'public.informe_jefe_departamento(text, integer, boolean)',
                           'public.listar_equipo(text)', 'public.informe_equipo(text, text[], boolean)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
revoke execute on function privado.conjunto(integer[], text, text[], jsonb) from public;
revoke execute on function privado.clases(smallint, integer[], jsonb, text) from public;
revoke execute on function privado.informe_partes(text, text, text, text[]) from public;
revoke execute on function privado.exigir_metrica_publica(jsonb) from public;
