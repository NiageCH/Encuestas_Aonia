-- Panel de Inicio con puntos de mejora (decisión del 22/10/2026):
--   * puntos fuertes y de mejora por colectivo: preguntas de 1 a 6 con su media y el porcentaje de 1 a 3;
--   * «En qué se diferencian quienes no recomendarían el Colegio»: nueva dimensión «recomienda»
--     (no_recomienda 0 a 6, recomienda 9 y 10, resto: 7 y 8 o sin respuesta), solo para la media de un bloque y
--     sin combinarse con ningún otro filtro; mínimo de 5 y complementaria entre los grupos.

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
    when 'recomienda'          then $e$coalesce(rr.grupo, 'resto')$e$
  end, '(sin dato)')
  where p_dim is not null;
$$;

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
    when 'alumnos'  then array['cuestionario', 'etapa', 'grupo', 'asignatura', 'recomienda']
    when 'familias' then array['etapa', 'recomienda']
    else array['docente', 'antiguedad', 'departamento_equipo', 'departamento', 'tramo', 'recomienda']
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
  v_recom     boolean := 'recomienda' = any(coalesce(p_dims, '{}'));
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
  if v_tipo = 'seleccion' and (v_asig or v_dep or v_tramo or v_atrib or v_recom) then
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

  -- Una pregunta que no está en estos cuestionarios no tiene celdas (antes daba error en las
  -- comprobaciones de abajo cuando se pedía la atribución por docente).
  if v_tipo = 'pregunta' and not exists (
    select 1 from public.pregunta_cuestionario pc where pc.cuestionario_id = any(p_cuest) and pc.pregunta_id = v_pregunta.id
  ) then
    return;
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

  -- Comparación por recomendación: solo bloques (media del bloque), sin otras dimensiones. Cada
  -- persona va al grupo de su recomendación: no la recomendaría (0 a 6), sí (9 y 10) o «resto»
  -- (7 y 8, o sin respuesta a la recomendación). Así no queda un grupo pequeño de quienes no la
  -- contestaron, que obligaría a ocultar otro por complementaria.
  if v_recom and (v_tipo <> 'bloque' or v_ndims > 1 or v_dep_met) then
    raise exception 'La comparación por recomendación solo vale para la media de un bloque, sin otros filtros';
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
              then ' left join privado.respuesta_docente rd on rd.respuesta_id = r.id and rd.asignatura_id = i.asignatura_id' else '' end
      || case when v_recom
              then ' left join lateral (select case when ri.valor <= 6 then ''no_recomienda'' when ri.valor >= 9 then ''recomienda'' else ''resto'' end as grupo
                      from privado.respuesta_item ri join public.pregunta rp on rp.id = ri.pregunta_id
                      where ri.respuesta_id = r.id and rp.tipo = ''recomendacion'' and ri.valor is not null limit 1) rr on true' else '' end;
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

-- Puntos fuertes y de mejora de un colectivo (panel de Inicio): las preguntas de 1 a 6 con la
-- media más alta y más baja, con el porcentaje que da de 1 a 3. Solo preguntas con 5 o más
-- valoraciones válidas; son totales del colectivo (o de la etapa de la coordinación), sin repartir.
create function public.puntos_colectivo(p_filtro jsonb, p_cuantos integer default 5)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_res    jsonb := privado.resolver(p_filtro, '{}');
  v_cuest  integer[] := array(select jsonb_array_elements_text(v_res -> 'cuestionarios')::integer);
  v_etapa  text := v_res -> 'fijos' ->> 'etapa';
  v_filas  jsonb;
begin
  if exists (select 1 from jsonb_object_keys(v_res -> 'fijos') k where k <> 'etapa') then
    raise exception 'Los puntos fuertes y de mejora son del total del colectivo, sin filtros';
  end if;
  select coalesce(jsonb_agg(x order by x ->> 'media'), '[]') into v_filas
  from (
    select jsonb_build_object('codigo', p.codigo_diccionario, 'texto', p.texto_es, 'n', count(i.valor),
             'media', avg(i.valor), 'pct_bajo', 100.0 * count(*) filter (where i.valor <= 3) / count(i.valor)) as x
    from privado.respuesta_item i
    join privado.respuesta r on r.id = i.respuesta_id
    join public.pregunta p on p.id = i.pregunta_id
    join public.pregunta_cuestionario pc on pc.cuestionario_id = r.cuestionario_id and pc.pregunta_id = i.pregunta_id
    where r.cuestionario_id = any(v_cuest)
      and p.tipo = 'escala' and p.escala_min = 1 and p.escala_max = 6 and not pc.por_departamento
      and i.valor is not null
      and (v_etapa is null or exists (select 1 from privado.respuesta_etapa re where re.respuesta_id = r.id and re.etapa = v_etapa))
    group by p.codigo_diccionario, p.texto_es
    having count(i.valor) >= 5
  ) t;
  return jsonb_build_object(
    'mejora', coalesce((select jsonb_agg(e order by (e ->> 'media')::numeric, (e ->> 'pct_bajo')::numeric desc)
                        from (select e from jsonb_array_elements(v_filas) e order by (e ->> 'media')::numeric, (e ->> 'pct_bajo')::numeric desc limit p_cuantos) z), '[]'),
    'fuertes', coalesce((select jsonb_agg(e order by (e ->> 'media')::numeric desc, (e ->> 'pct_bajo')::numeric)
                        from (select e from jsonb_array_elements(v_filas) e order by (e ->> 'media')::numeric desc, (e ->> 'pct_bajo')::numeric limit p_cuantos) z), '[]'));
end $$;

-- En qué se diferencian quienes no recomendarían el Colegio (0 a 6) de quienes sí (9 y 10):
-- media de cada bloque de 1 a 6 en los dos grupos, con el mínimo de 5 y la complementaria entre
-- los grupos (incluido el «resto»: 7 y 8, o sin respuesta a la recomendación). Es una
-- comparación, no una causa. Solo administración y dirección, sin filtros.
create function public.comparacion_recomendacion(p_curso text, p_colectivo text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_filtro jsonb := jsonb_build_object('curso', p_curso, 'colectivo', p_colectivo);
  v_cuest  integer[];
  v_b      record;
  v_r      jsonb;
  v_no     jsonb;
  v_si     jsonb;
  v_salida jsonb := '[]';
begin
  perform permisos.exigir();
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a la comparación por recomendación' using errcode = '42501';
  end if;
  v_cuest := array(select jsonb_array_elements_text(privado.resolver(v_filtro, '{}') -> 'cuestionarios')::integer);
  for v_b in
    select b.codigo, min(b.nombre) as nombre, min(b.orden) as orden
    from public.bloque b
    join public.pregunta_cuestionario pc on pc.bloque_id = b.id
    join public.pregunta p on p.id = pc.pregunta_id
    where b.cuestionario_id = any(v_cuest) and p.tipo = 'escala' and p.escala_min = 1 and p.escala_max = 6
    group by b.codigo
    having not bool_or(pc.por_departamento)
    order by min(b.orden), b.codigo
  loop
    v_r := public.resultados(v_filtro, jsonb_build_object('tipo', 'bloque', 'codigo', v_b.codigo), '{recomienda}');
    select p into v_no from jsonb_array_elements(v_r -> 'partes') p where p -> 'clave' ->> 'recomienda' = 'no_recomienda';
    select p into v_si from jsonb_array_elements(v_r -> 'partes') p where p -> 'clave' ->> 'recomienda' = 'recomienda';
    v_salida := v_salida || jsonb_build_object('bloque', v_b.codigo, 'nombre', v_b.nombre,
      'no_recomienda', coalesce(v_no, jsonb_build_object('suprimido', true, 'motivo', 'sin_datos')),
      'recomienda', coalesce(v_si, jsonb_build_object('suprimido', true, 'motivo', 'sin_datos')),
      'diferencia', case when not coalesce((v_no ->> 'suprimido')::boolean, true) and not coalesce((v_si ->> 'suprimido')::boolean, true)
                         then (v_si ->> 'media')::numeric - (v_no ->> 'media')::numeric end);
  end loop;
  return coalesce((select jsonb_agg(x order by (x ->> 'diferencia')::numeric desc nulls last) from jsonb_array_elements(v_salida) x), '[]');
end $$;

revoke execute on function public.puntos_colectivo(jsonb, integer) from public, anon;
grant execute on function public.puntos_colectivo(jsonb, integer) to authenticated;
revoke execute on function public.comparacion_recomendacion(text, text) from public, anon;
grant execute on function public.comparacion_recomendacion(text, text) to authenticated;
