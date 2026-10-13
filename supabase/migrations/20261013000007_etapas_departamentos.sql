-- Cambios del modelo tras revisar las exportaciones reales (decisiones del 13/10/2026):
--
-- 1. Familias con varias etapas: una familia marca todos los cursos de sus hijos. La etapa
--    pasa a una tabla privado.respuesta_etapa (respuesta, etapa). En el reparto por etapa
--    la familia cuenta en cada etapa que marcó; en el total cuenta una vez.
-- 2. Bloque "Reuniones de departamento" (personal): el departamento es una dimensión del
--    ítem, como la asignatura en alumnos. Solo se consulta repartido por departamento y
--    nunca se cruza con otras respuestas de la misma persona (segmentos u otros bloques).
-- 3. Alumnos sin grupo: algunas respuestas no indican grupo. Cuentan en el total del
--    cuestionario y nunca forman un grupo propio.
-- 4. n de personas = personas con al menos una valoración válida (o una opción marcada) en
--    el conjunto. Se cargan también las respuestas abandonadas, con lo que contestaron.

-- 1. Etapas de familias -------------------------------------------------------------------

create table privado.respuesta_etapa (
  respuesta_id  bigint not null references privado.respuesta on delete cascade,
  etapa         text not null references public.etapa,
  primary key (respuesta_id, etapa)
);

create function privado.validar_respuesta_etapa() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (
    select 1 from privado.respuesta r join public.cuestionario c on c.id = r.cuestionario_id
    where r.id = new.respuesta_id and c.colectivo = 'familias'
  ) then
    raise exception 'Solo las respuestas de familias llevan etapas propias';
  end if;
  return new;
end $$;

create trigger respuesta_etapa_validar
  before insert or update on privado.respuesta_etapa
  for each row execute function privado.validar_respuesta_etapa();

alter table privado.respuesta drop column etapa;

-- 3. Coherencia con el colectivo, sin etapa en la respuesta y con grupo opcional en alumnos.
create or replace function privado.validar_respuesta() returns trigger
language plpgsql set search_path = '' as $$
declare
  c public.cuestionario;
  g public.grupo;
begin
  select * into c from public.cuestionario where id = new.cuestionario_id;
  if c.colectivo = 'alumnos' then
    if new.grupo_id is not null then
      select * into g from public.grupo where id = new.grupo_id;
      if g.curso_id <> c.curso_id or g.etapa <> c.etapa then
        raise exception 'El grupo % no corresponde al curso o la etapa del cuestionario', g.nombre;
      end if;
    end if;
    if new.docente is not null or new.antiguedad is not null or new.departamento_equipo is not null then
      raise exception 'Los segmentos de personal no aplican a alumnos';
    end if;
  elsif c.colectivo = 'familias' then
    if new.grupo_id is not null or new.docente is not null or new.antiguedad is not null
       or new.departamento_equipo is not null then
      raise exception 'Una respuesta de familias no lleva grupo ni segmentos de personal';
    end if;
  else
    if new.grupo_id is not null then
      raise exception 'Una respuesta de personal no lleva grupo';
    end if;
  end if;
  return new;
end $$;

-- 2. Departamento como dimensión del ítem ------------------------------------------------

alter table public.pregunta_cuestionario
  add column por_departamento boolean not null default false,
  add constraint pregunta_cuestionario_una_dimension check (not (por_asignatura and por_departamento));

alter table privado.respuesta_item
  add column departamento_id integer references public.departamento,
  drop constraint respuesta_item_respuesta_id_pregunta_id_asignatura_id_key,
  add constraint respuesta_item_unica unique nulls not distinct (respuesta_id, pregunta_id, asignatura_id, departamento_id);

create or replace function privado.validar_respuesta_item() returns trigger
language plpgsql set search_path = '' as $$
declare
  p public.pregunta;
  pc public.pregunta_cuestionario;
begin
  select * into p from public.pregunta where id = new.pregunta_id;
  select pc2.* into pc
  from public.pregunta_cuestionario pc2
  join privado.respuesta r on r.cuestionario_id = pc2.cuestionario_id
  where r.id = new.respuesta_id and pc2.pregunta_id = new.pregunta_id;
  if not found then
    raise exception 'La pregunta % no pertenece al cuestionario de la respuesta', p.codigo_diccionario;
  end if;
  if p.tipo = 'seleccion_multiple' then
    raise exception 'La selección múltiple va en respuesta_opcion';
  end if;
  if new.valor is not null and (new.valor < p.escala_min or new.valor > p.escala_max) then
    raise exception 'Valor % fuera de la escala de % a % en %',
      new.valor, p.escala_min, p.escala_max, p.codigo_diccionario;
  end if;
  if pc.por_asignatura <> (new.asignatura_id is not null) then
    raise exception 'La pregunta % % lleva asignatura', p.codigo_diccionario,
      case when pc.por_asignatura then 'sí' else 'no' end;
  end if;
  if pc.por_departamento <> (new.departamento_id is not null) then
    raise exception 'La pregunta % % lleva departamento', p.codigo_diccionario,
      case when pc.por_departamento then 'sí' else 'no' end;
  end if;
  return new;
end $$;

alter table privado.respuesta_etapa enable row level security;
revoke all on privado.respuesta_etapa from public, anon, authenticated;
grant select, insert, update, delete on privado.respuesta_etapa to service_role;

-- Motor ----------------------------------------------------------------------------------

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
  end, '(sin dato)')
  where p_dim is not null;
$$;

-- Igual que antes, con "departamento" (dimensión del ítem) entre las claves de personal.
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
    else array['docente', 'antiguedad', 'departamento_equipo', 'departamento']
  end;

  for k in select jsonb_object_keys(v_filtro) loop
    if k not in ('curso', 'colectivo') and not k = any(v_particion) then
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
    and (v_col <> 'alumnos' or not v_filtro ? 'cuestionario' or c.codigo = v_filtro ->> 'cuestionario');
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
    where d in ('docente', 'antiguedad', 'departamento_equipo');
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

-- Celdas y márgenes de una métrica (ver la migración 4 para la lista de métricas).
-- Novedades:
--   * etapa: en familias una respuesta puede tener varias etapas. Las filas por etapa se
--     calculan uniendo respuesta_etapa (la familia cuenta en cada etapa) y los márgenes sin
--     etapa se calculan sin esa unión (la familia cuenta una vez).
--   * departamento: solo para las preguntas por departamento, y solo repartidas por
--     departamento. Ninguna otra dimensión ni métrica las cruza.
--   * personas: solo cuenta quien tiene al menos una valoración válida u opción marcada.
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
  v_dep_met   boolean := false;
  v_from      text;
  v_where     text;
  v_n         text;
  v_datos     text;
  v_rec       boolean := false;
  v_dist_min  integer;
  v_dist_max  integer;
  v_pe        integer;   -- posición de la dimensión etapa (1 o 2), si la hay
  v_po        integer;   -- posición de la otra dimensión cuando hay etapa
  v_sql       text;
  e           text[];
  d           text;
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
  if v_tipo = 'seleccion' and (v_asig or v_dep) then
    raise exception 'La selección múltiple no se reparte por asignatura ni por departamento';
  end if;

  -- Bloque por departamento: aislado del resto de respuestas de la persona.
  v_dep_met := case
    when v_tipo = 'bloque' then exists (
      select 1 from public.pregunta_cuestionario pc join public.bloque b on b.id = pc.bloque_id
      where pc.cuestionario_id = any(p_cuest) and b.codigo = v_cod and pc.por_departamento)
    when v_tipo = 'pregunta' then exists (
      select 1 from public.pregunta_cuestionario pc
      where pc.cuestionario_id = any(p_cuest) and pc.pregunta_id = v_pregunta.id and pc.por_departamento)
    else false
  end;
  if v_dep_met and (not v_dep or v_ndims > 1) then
    raise exception 'Las reuniones de departamento solo se consultan repartidas por departamento, sin otros filtros';
  end if;
  if v_dep and not v_dep_met then
    raise exception 'La dimensión departamento solo vale para las reuniones de departamento';
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
      join public.bloque b on b.id = pc.bloque_id';
    v_where := 'r.cuestionario_id = any($1)' || case v_tipo
      when 'personas'      then ' and i.valor is not null'
      when 'satisfaccion'  then ' and p.tipo = ''escala'' and p.escala_min = 1 and p.escala_max = 6 and b.entra_en_media'
      when 'bloque'        then ' and p.tipo = ''escala'' and b.codigo = $2'
      when 'pregunta'      then ' and i.pregunta_id = $3'
      when 'recomendacion' then ' and p.tipo = ''recomendacion'''
    end;
    -- Las preguntas por departamento solo entran en su propia métrica.
    v_where := v_where || case when v_dep_met then ' and pc.por_departamento' else ' and not pc.por_departamento' end;
    if v_asig then
      v_where := v_where || ' and i.asignatura_id is not null';
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
    -- Filas con etapa: uniendo respuesta_etapa (una familia cuenta en cada etapa marcada).
    -- Márgenes sin etapa: sin esa unión (cuenta una vez).
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
  using p_cuest, v_cod, v_pregunta.id;
end $$;
