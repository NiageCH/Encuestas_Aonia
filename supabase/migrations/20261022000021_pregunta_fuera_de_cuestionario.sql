-- Fallo encontrado el 22/10/2026 al preparar la revisión con los datos reales: el informe de un
-- profesor con clases en varios cuestionarios daba error si una pregunta de profesorado solo
-- existía en uno de ellos y en otro tenía respuestas atribuidas por nombre. Ahora, una pregunta
-- que no está en un cuestionario no aporta celdas de ese cuestionario, y las clases sin celdas se
-- saltan. Además, una asignatura sin titulares por grupo (la optativa) ya no aparece también
-- grupo a grupo: solo por cuestionario, como «todos sus grupos» (antes salía dos veces y contaba
-- doble en la media global). Tests en supabase/tests/09_jefes_tramos_atribucion.sql.

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

create or replace function privado.clases(p_curso smallint, p_docentes integer[], p_metrica jsonb, p_etapa text default null)
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

      select array_agg(y.k1), array_agg(y.agg1), array_agg(y.n), array_agg(y.datos)
        into b_k1, b_g1, b_n, b_d
      from privado.celdas(array[v_c.id], array['docente_atribuido'],
             p_metrica || jsonb_build_object('grupo_id', v_gid, 'asignatura_id', v_aid)) y;
      continue when b_n is null;
      b_mot := privado.suprimir(b_k1, array_fill(null::text, array[cardinality(b_n)]), b_g1,
                                array_fill(true, array[cardinality(b_n)]), b_n);
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
      select array_agg(y.k1), array_agg(y.agg1), array_agg(y.n), array_agg(y.datos)
        into b_k1, b_g1, b_n, b_d
      from privado.celdas(array[v_c.id], array['docente_atribuido'],
             p_metrica || jsonb_build_object('asignatura_id', v_a.asignatura_id)) y;
      continue when b_n is null;
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
