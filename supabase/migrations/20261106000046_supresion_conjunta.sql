-- Supresión complementaria conjunta (06/11/2026, especificación §5): el mínimo de 5 y la complementaria ya no se deciden
-- tabla a tabla, sino a la vez en todas las tablas que se pueden comparar entre sí. Antes, quien tiene el criterio de la
-- coordinación (y la versión docente y la de la jefatura) podía pedir la tabla de un bloque y la de cada una de sus
-- preguntas con los mismos filtros y despejar una celda oculta restando: la media de un bloque es la de todas las
-- valoraciones de sus preguntas, y cada celda lleva su número de valoraciones. Lo mismo con la satisfacción general,
-- que junta las preguntas de 1 a 6 de los bloques que entran en la media.
--
-- Cómo se decide (privado.suprimir_relacionada): cada total con sus partes forma una relación (en una tabla, cada margen
-- con sus celdas; entre tablas, en cada celda, el bloque con sus preguntas y la satisfacción general con sus bloques y
-- con sus preguntas). En ninguna relación puede quedar oculto uno solo de sus miembros: si pasa, se oculta también la
-- parte visible con menos respuestas (o el total, si no queda ninguna parte visible), y se repite hasta que no cambie
-- nada. Además cubre un caso que la versión anterior no miraba: un total oculto con todas sus partes visibles.
--
-- Dirección y administración no cambian: siguen viéndolo todo, con la marca «menos de 5».

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
  v_fam       boolean := v_tipo = 'familia';
  v_pz        text;
  v_pre       text := '';
begin
  -- Familia (uso interno de privado.celdas_suprimidas, nunca desde fuera): las preguntas de escala, o los bloques,
  -- como una dimensión más («pieza»), con los mismos filtros que la métrica que se pide.
  if v_fam then
    v_pz := case p_metrica ->> 'nivel' when 'bloque' then 'b.codigo' else 'p.codigo_diccionario' end;
    v_pre := v_pz || ', ';
    v_dep_met := coalesce((p_metrica ->> 'departamental')::boolean, false);
    v_ei_met := coalesce((p_metrica ->> 'equipo')::boolean, false);
  else
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
      when 'familia'       then ' and p.tipo = ''escala''' || case when v_ei_met then ' and b.codigo = ''equipo_individualizacion''' else '' end
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

    v_n := case when v_tipo in ('pregunta', 'recomendacion') or v_pz = 'p.codigo_diccionario' then 'count(i.valor)'
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

    if v_fam then
      v_datos := format('jsonb_build_object(''pieza'', %s)', v_pz);
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
        when 0 then coalesce('group by ' || v_pz, '')
        when 1 then format('group by grouping sets ((%2$s%1$s), (%3$s))', e[1], v_pre, coalesce(v_pz, ''))
        else format('group by grouping sets ((%3$s%1$s, %2$s), (%3$s%1$s), (%3$s%2$s), (%4$s))', e[1], e[2], v_pre, coalesce(v_pz, ''))
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
      case when v_po is null then format('group by %s%s', v_pre, e[v_pe])
           else format('group by grouping sets ((%3$s%1$s, %2$s), (%3$s%1$s))', e[v_pe], e[v_po], v_pre) end)
    || ' union all ' ||
    format(
      'select %s, %s, %s, %s, (%s)::integer, %s from %s where %s %s',
      case when v_pe = 1 then 'null::text' else coalesce(e[1], 'null::text') end,
      case when v_pe = 2 then 'null::text' else coalesce(e[2], 'null::text') end,
      case when v_pe = 1 then 'true' when e[1] is null then 'true' else format('grouping(%s) = 1', e[1]) end,
      case when v_pe = 2 then 'true' when e[2] is null then 'true' else format('grouping(%s) = 1', e[2]) end,
      v_n, v_datos, v_from, v_where,
      case when v_po is null then coalesce('group by ' || v_pz, '')
           else format('group by grouping sets ((%2$s%1$s), (%3$s))', e[v_po], v_pre, coalesce(v_pz, '')) end);
  end if;

  return query execute format('select * from (%s) t order by 1 nulls first, 2 nulls first', v_sql)
  using p_cuest, v_cod, v_pregunta.id, v_tramos, v_deps, v_grupo, v_asig_id;
end $$;


-- Clases de los docentes: las mismas celdas, con la supresión conjunta.
CREATE OR REPLACE FUNCTION privado.clases(p_curso smallint, p_docentes integer[], p_metrica jsonb, p_etapa text DEFAULT NULL::text)
 RETURNS TABLE(docente_id integer, cuestionario text, etapa text, grupo text, asignatura text, tipo text, docentes_clase integer, motivo text, n integer, datos jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_atr      integer[];
  v_todos    integer[];
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
    select array_agg(x.k1), array_agg(x.k2), array_agg(x.agg1), array_agg(x.agg2), array_agg(x.n), array_agg(x.datos), array_agg(x.motivo)
      into a_k1, a_k2, a_g1, a_g2, a_n, a_d, v_mot
    from privado.celdas_suprimidas(array[v_c.id], array['grupo', 'asignatura'], p_metrica) x;

    for i in 1 .. coalesce(cardinality(a_n), 0) loop
      continue when a_g1[i] or a_g2[i];
      select g.id into v_gid from public.grupo g where g.curso_id = p_curso and g.nombre = a_k1[i];
      select a.id into v_aid from public.asignatura a where a.curso_id = p_curso and a.nombre = a_k2[i];
      select array_agg(ad.docente_id order by ad.docente_id) into v_doc
      from public.asignacion_docente ad
      where ad.curso_id = p_curso and ad.grupo_id = v_gid and ad.asignatura_id = v_aid;
      -- Docentes atribuidos por nombre en esta clase (pueden no ser los titulares de Alexia).
      select array_agg(distinct rd.docente_id) into v_atr
      from privado.respuesta_docente rd join privado.respuesta r on r.id = rd.respuesta_id
      where r.cuestionario_id = v_c.id and r.grupo_id = v_gid and rd.asignatura_id = v_aid;
      -- Sin titular en Alexia para esta clase (las optativas): va por cuestionario, más abajo.
      continue when v_doc is null;
      v_todos := array(select distinct x from unnest(coalesce(v_doc, '{}') || coalesce(v_atr, '{}')) x order by x);
      continue when cardinality(v_todos) = 0 or not (v_todos && p_docentes);

      if v_atr is null and cardinality(v_doc) = 1 then
        return query select v_doc[1], v_c.codigo, v_c.etapa, a_k1[i], a_k2[i], 'propia'::text, 1, v_mot[i], a_n[i], a_d[i];
        continue;
      end if;

      if v_atr is null then
        return query select x, v_c.codigo, v_c.etapa, a_k1[i], a_k2[i], 'compartida'::text, cardinality(v_doc), v_mot[i], a_n[i], a_d[i]
                     from unnest(v_doc) x where x = any(p_docentes);
        continue;
      end if;

      select array_agg(y.k1), array_agg(y.agg1), array_agg(y.n), array_agg(y.datos), array_agg(y.motivo)
        into b_k1, b_g1, b_n, b_d, b_mot
      from privado.celdas_suprimidas(array[v_c.id], array['docente_atribuido'],
             p_metrica || jsonb_build_object('grupo_id', v_gid, 'asignatura_id', v_aid)) y;
      continue when b_n is null;
      -- Cada docente nombrado recibe su subconjunto. Un titular al que no nombró nadie (por
      -- ejemplo, de baja) no recibe nada de esta clase.
      foreach v_d in array v_todos loop
        continue when not v_d = any(p_docentes);
        j := null;
        for k in 1 .. cardinality(b_n) loop
          if not b_g1[k] and b_k1[k] = v_d::text then j := k; end if;
        end loop;
        continue when j is null;
        return query select v_d, v_c.codigo, v_c.etapa, a_k1[i], a_k2[i], 'atribuida'::text, cardinality(v_todos),
                            case when v_mot[i] is not null then coalesce(b_mot[j], 'complementaria') else b_mot[j] end, b_n[j], b_d[j];
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
      select array_agg(y.k1), array_agg(y.agg1), array_agg(y.n), array_agg(y.datos), array_agg(y.motivo)
        into b_k1, b_g1, b_n, b_d, b_mot
      from privado.celdas_suprimidas(array[v_c.id], array['docente_atribuido'],
             p_metrica || jsonb_build_object('asignatura_id', v_a.asignatura_id)) y;
      continue when b_n is null;
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
end $function$;

-- Partes de un responsable juntas: igual.
CREATE OR REPLACE FUNCTION privado.conjunto(p_cuest integer[], p_dim text, p_valores text[], p_metrica jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  select array_agg(x.k1), array_agg(x.k2), array_agg(x.agg1), array_agg(x.agg2), array_agg(x.n), array_agg(x.datos), array_agg(x.motivo)
    into a_k1, a_k2, a_g1, a_g2, a_n, a_d, v_mot
  from privado.celdas_suprimidas(p_cuest, array[p_dim], p_metrica) x;
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
  return privado.fila('{}', privado.motivo_minimo(v_n), v_n, v_datos);
end $function$;

-- Supresión sobre un conjunto de tablas relacionadas. p_t: tabla de cada celda; p_rp y p_rh: pares de tablas
-- (total, parte) que se relacionan en cada celda con la misma clave. Devuelve el motivo de cada celda (null si se ve).
create or replace function privado.suprimir_relacionada(p_t text[], p_k1 text[], p_k2 text[], p_g1 boolean[], p_g2 boolean[],
                                                        p_n integer[], p_rp text[], p_rh text[])
returns text[]
language plpgsql volatile set search_path = '' as $$
declare
  v_len    integer := coalesce(cardinality(p_n), 0);
  v_mot    text[] := array_fill(null::text, array[v_len]);
  v_r      text[];
  v_m      integer[];
  v_total  boolean[];
  v_nuevos integer[];
  i integer;
begin
  for i in 1 .. v_len loop
    if coalesce(p_n[i], 0) < 5 then v_mot[i] := 'menos_de_5'; end if;
  end loop;
  if v_len = 0 then return v_mot; end if;

  with c as (
    select g.x as i, p_t[g.x] as t, p_k1[g.x] as k1, p_k2[g.x] as k2, p_g1[g.x] as g1, p_g2[g.x] as g2 from generate_subscripts(p_n, 1) g(x)
  ), rel as (
    select distinct rp, rh from unnest(coalesce(p_rp, '{}'), coalesce(p_rh, '{}')) u(rp, rh)
  ), pares as (
    -- En cada tabla, cada margen con sus celdas (por una dimensión y por la otra).
    select 'a' || m.i as r, m.i as total, x.i as parte
    from c m join c x on x.t = m.t and m.g1 and not x.g1 and x.g2 = m.g2 and (m.g2 or x.k2 is not distinct from m.k2)
    union all
    select 'b' || m.i, m.i, x.i
    from c m join c x on x.t = m.t and m.g2 and not x.g2 and x.g1 = m.g1 and (m.g1 or x.k1 is not distinct from m.k1)
    union all
    -- Entre tablas, en la misma celda: el total (bloque o satisfacción) con sus partes: el bloque con sus preguntas;
    -- la satisfacción general con sus bloques, y aparte con sus preguntas.
    select 'c' || m.i || ':' || left(rel.rh, 1), m.i, x.i
    from c m join rel on rel.rp = m.t
    join c x on x.t = rel.rh and x.g1 = m.g1 and x.g2 = m.g2 and x.k1 is not distinct from m.k1 and x.k2 is not distinct from m.k2
  ), miembros as (
    select distinct r, total as m, true as es_total from pares
    union all
    select r, parte, false from pares
  )
  select array_agg(r), array_agg(m), array_agg(es_total) into v_r, v_m, v_total from miembros;

  -- En cada vuelta, cada relación con un solo oculto elige a quién ocultar: primero una parte (no el total) y, como
  -- siempre, la de menos respuestas. Entre tablas (bloque, preguntas y satisfacción), antes que eso, la parte que más
  -- relaciones arregla a la vez (otras con un solo oculto) y menos abre (otras sin ninguno): si queda oculta una
  -- pregunta, se elige otra del mismo bloque antes que una pregunta suelta de otro, que obligaría a ocultar su bloque.
  loop
    with d as (
      select distinct r, m, es_total from unnest(v_r, v_m, v_total) u(r, m, es_total)
    ), z as (
      select r, m, es_total, count(*) filter (where v_mot[m] is not null) over (partition by r) as ocultos from d
    ), efecto as (
      select m, count(*) filter (where ocultos = 0) - count(*) filter (where ocultos = 1) as coste from z group by m
    )
    select array_agg(distinct y.m) into v_nuevos from (
      select distinct on (z.r) z.m from z join efecto e on e.m = z.m
      where z.ocultos = 1 and v_mot[z.m] is null
      order by z.r, z.es_total, case when left(z.r, 1) = 'c' then e.coste else 0 end, p_n[z.m], z.m
    ) y;
    exit when v_nuevos is null;
    foreach i in array v_nuevos loop
      v_mot[i] := 'complementaria';
    end loop;
  end loop;
  return v_mot;
end $$;

revoke execute on function privado.suprimir_relacionada(text[], text[], text[], boolean[], boolean[], integer[], text[], text[])
  from public, anon, authenticated;

-- Celdas de una métrica con su motivo de supresión, decidido a la vez con todas las tablas relacionadas con ella (sin
-- supresión para Dirección y administración fuera de la versión docente). Dentro de una misma consulta (por ejemplo,
-- el informe de un docente, que pide el bloque y cada pregunta) el cálculo de la familia se hace una vez.
create or replace function privado.celdas_suprimidas(p_cuest integer[], p_dims text[], p_metrica jsonb)
returns table (k1 text, k2 text, agg1 boolean, agg2 boolean, n integer, datos jsonb, motivo text)
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_tipo    text := p_metrica ->> 'tipo';
  v_cod     text := p_metrica ->> 'codigo';
  v_dims    text[] := coalesce(p_dims, '{}');
  v_extra   jsonb := p_metrica - 'tipo' - 'codigo';
  v_fam     boolean;
  v_dep     boolean := false;
  v_ei      boolean;
  v_satisf  boolean;
  v_tabla   text;
  v_clave   text;
  v_cache   jsonb;
  a_t text[]; a_k1 text[]; a_k2 text[]; a_g1 boolean[]; a_g2 boolean[]; a_n integer[]; a_d jsonb[];
  s_k1 text[]; s_k2 text[]; s_g1 boolean[]; s_g2 boolean[]; s_n integer[];
  v_rp      text[] := '{}';
  v_rh      text[] := '{}';
  v_mot     text[];
begin
  if privado.ve_menos_de_5() then
    return query select x.k1, x.k2, x.agg1, x.agg2, x.n, x.datos, null::text from privado.celdas(p_cuest, p_dims, p_metrica) x;
    return;
  end if;

  v_fam := (v_tipo in ('bloque', 'satisfaccion')
            or (v_tipo = 'pregunta' and exists (select 1 from public.pregunta p where p.codigo_diccionario = v_cod and p.tipo = 'escala')))
           and not 'recomienda' = any(v_dims);

  if not v_fam then
    -- Una tabla sola: cada margen con sus celdas.
    select array_agg(x.k1), array_agg(x.k2), array_agg(x.agg1), array_agg(x.agg2), array_agg(x.n), array_agg(x.datos)
      into a_k1, a_k2, a_g1, a_g2, a_n, a_d
    from privado.celdas(p_cuest, p_dims, p_metrica) x;
    v_mot := privado.suprimir_relacionada(array_fill('t'::text, array[coalesce(cardinality(a_n), 0)]), a_k1, a_k2, a_g1, a_g2, a_n, '{}', '{}');
    return query select u.k1, u.k2, u.g1, u.g2, u.n, u.d, u.m from unnest(a_k1, a_k2, a_g1, a_g2, a_n, a_d, v_mot) u(k1, k2, g1, g2, n, d, m);
    return;
  end if;

  if v_tipo = 'bloque' then
    select coalesce(bool_or(pc.por_departamento), false) into v_dep
    from public.pregunta_cuestionario pc join public.bloque b on b.id = pc.bloque_id
    where pc.cuestionario_id = any(p_cuest) and b.codigo = v_cod;
  elsif v_tipo = 'pregunta' then
    select coalesce(bool_or(pc.por_departamento), false) into v_dep
    from public.pregunta_cuestionario pc join public.pregunta p on p.id = pc.pregunta_id
    where pc.cuestionario_id = any(p_cuest) and p.codigo_diccionario = v_cod;
  end if;
  v_ei := 'tramo' = any(v_dims) or v_extra ? 'tramos';
  -- La satisfacción general solo se puede pedir sin estos filtros: con ellos no hay con qué comparar.
  v_satisf := not v_dep and not v_ei and not 'docente_atribuido' = any(v_dims)
              and not (v_extra ?| array['grupo_id', 'asignatura_id', 'tramos', 'departamentos']);
  v_tabla := case v_tipo when 'satisfaccion' then 'S' when 'bloque' then 'B:' || v_cod else 'Q:' || v_cod end;

  v_clave := 'encuestas.f' || md5(concat_ws('|', p_cuest::text, v_dims::text, v_extra::text, v_dep, v_ei, statement_timestamp()));
  v_cache := nullif(current_setting(v_clave, true), '')::jsonb;

  if v_cache is null then
    select array_agg(f.t), array_agg(f.k1), array_agg(f.k2), array_agg(f.agg1), array_agg(f.agg2), array_agg(f.n)
      into a_t, a_k1, a_k2, a_g1, a_g2, a_n
    from (
      select 'Q:' || (x.datos ->> 'pieza') as t, x.k1, x.k2, x.agg1, x.agg2, x.n
      from privado.celdas(p_cuest, p_dims, v_extra || jsonb_build_object('tipo', 'familia', 'nivel', 'pregunta',
             'departamental', v_dep, 'equipo', v_ei)) x
      union all
      select 'B:' || (x.datos ->> 'pieza'), x.k1, x.k2, x.agg1, x.agg2, x.n
      from privado.celdas(p_cuest, p_dims, v_extra || jsonb_build_object('tipo', 'familia', 'nivel', 'bloque',
             'departamental', v_dep, 'equipo', v_ei)) x
    ) f;
    if v_satisf then
      select array_agg(x.k1), array_agg(x.k2), array_agg(x.agg1), array_agg(x.agg2), array_agg(x.n)
        into s_k1, s_k2, s_g1, s_g2, s_n
      from privado.celdas(p_cuest, p_dims, '{"tipo": "satisfaccion"}') x;
      a_t := a_t || array_fill('S'::text, array[coalesce(cardinality(s_n), 0)]);
      a_k1 := a_k1 || s_k1; a_k2 := a_k2 || s_k2; a_g1 := a_g1 || s_g1; a_g2 := a_g2 || s_g2; a_n := a_n || s_n;
    end if;

    -- Qué es parte de qué: cada pregunta, de su bloque; y en la satisfacción general, los bloques y las preguntas que
    -- entran en ella.
    select coalesce(array_agg(x.rp), '{}'), coalesce(array_agg(x.rh), '{}') into v_rp, v_rh from (
      select distinct 'B:' || b.codigo as rp, 'Q:' || p.codigo_diccionario as rh
      from public.pregunta_cuestionario pc join public.pregunta p on p.id = pc.pregunta_id join public.bloque b on b.id = pc.bloque_id
      where pc.cuestionario_id = any(p_cuest) and p.tipo = 'escala'
      union
      select 'S', 'Q:' || p.codigo_diccionario
      from public.pregunta_cuestionario pc join public.pregunta p on p.id = pc.pregunta_id join public.bloque b on b.id = pc.bloque_id
      where v_satisf and pc.cuestionario_id = any(p_cuest) and p.tipo = 'escala' and p.escala_min = 1 and p.escala_max = 6 and b.entra_en_media
      union
      select 'S', 'B:' || b.codigo
      from public.pregunta_cuestionario pc join public.pregunta p on p.id = pc.pregunta_id join public.bloque b on b.id = pc.bloque_id
      where v_satisf and pc.cuestionario_id = any(p_cuest) and p.tipo = 'escala' and p.escala_min = 1 and p.escala_max = 6 and b.entra_en_media
    ) x;

    v_mot := privado.suprimir_relacionada(a_t, a_k1, a_k2, a_g1, a_g2, a_n, v_rp, v_rh);
    select coalesce(jsonb_object_agg(concat_ws(chr(31), u.t, coalesce(u.k1, '~'), coalesce(u.k2, '~'), u.g1, u.g2), coalesce(u.m, '')),
                    '{}') || '{"_": ""}'
      into v_cache
    from unnest(a_t, a_k1, a_k2, a_g1, a_g2, v_mot) u(t, k1, k2, g1, g2, m);
    perform set_config(v_clave, v_cache::text, true);
  end if;

  -- Una celda que no estuviera en la familia (no debería pasar) se oculta.
  return query
    select x.k1, x.k2, x.agg1, x.agg2, x.n, x.datos,
           nullif(coalesce(v_cache ->> concat_ws(chr(31), v_tabla, coalesce(x.k1, '~'), coalesce(x.k2, '~'), x.agg1, x.agg2),
                           'complementaria'), '')
    from privado.celdas(p_cuest, p_dims, p_metrica) x;
end $$;

revoke execute on function privado.celdas_suprimidas(integer[], text[], jsonb) from public, anon, authenticated;

-- La métrica «familia» es solo interna: desde fuera, solo las de siempre.
create or replace function privado.exigir_metrica_publica(p_metrica jsonb) returns void
language plpgsql immutable set search_path = '' as $$
declare k text;
begin
  for k in select jsonb_object_keys(coalesce(p_metrica, '{}')) loop
    if k not in ('tipo', 'codigo') then
      raise exception 'Métrica no válida: %', k;
    end if;
  end loop;
  if coalesce(p_metrica ->> 'tipo', '') not in ('personas', 'satisfaccion', 'bloque', 'pregunta', 'recomendacion', 'seleccion') then
    raise exception 'Métrica no válida: %', coalesce(p_metrica ->> 'tipo', '(vacía)');
  end if;
end $$;

-- Resultados públicos: igual que antes, con la supresión conjunta.
create or replace function public.resultados(p_filtro jsonb, p_metrica jsonb, p_dimensiones text[] default '{}')
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
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

  select array_agg(c.k1), array_agg(c.k2), array_agg(c.agg1), array_agg(c.agg2), array_agg(c.n), array_agg(c.datos), array_agg(c.motivo)
    into a_k1, a_k2, a_g1, a_g2, a_n, a_d, v_mot
  from privado.celdas_suprimidas(v_cuest, v_dims, p_metrica) c;

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
