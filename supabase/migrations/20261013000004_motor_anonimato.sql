-- Motor de agregación con el mínimo de 5 y supresión complementaria. Especificación §3 y §5.
--
-- Idea central: un filtro que selecciona una parte de un total (un grupo, una asignatura,
-- la etapa en familias, un segmento de personal) se convierte en una dimensión del
-- conjunto completo. Así el estado de cada parte (visible o suprimida) se calcula siempre
-- dentro de su partición entera y es el mismo tanto si se pide la parte sola como si se
-- pide el reparto completo. Pedir "el grupo suprimido por complementaria" directamente
-- no lo destapa.

-- Expresión SQL de cada dimensión. Los valores nulos se agrupan como "(sin dato)".
create function privado.expr_dim(p_dim text) returns text
language sql immutable set search_path = '' as $$
  select format('coalesce(%s, %L)', case p_dim
    when 'grupo'               then 'g.nombre'
    when 'asignatura'          then 'a.nombre'
    when 'etapa'               then 'coalesce(r.etapa, g.etapa, c.etapa)'
    when 'cuestionario'        then 'c.codigo'
    when 'docente'             then $e$case r.docente when true then 'docente' when false then 'no_docente' end$e$
    when 'antiguedad'          then 'r.antiguedad'
    when 'departamento_equipo' then 'r.departamento_equipo'
  end, '(sin dato)')
  where p_dim is not null;
$$;

-- Valida el filtro y los permisos, y devuelve el ámbito resuelto:
--   cuestionarios: ids del conjunto completo sobre el que se calcula
--   dims:          dimensiones del cálculo (claves de partición del filtro + las pedidas)
--   fijos:         valor fijado para cada dimensión que venía en el filtro
--   salida:        dimensiones que se devuelven repartidas
create function privado.resolver(p_filtro jsonb, p_dims text[])
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_perfil     public.usuario_perfil := permisos.exigir();
  v_filtro     jsonb := coalesce(p_filtro, '{}');
  v_col        text := v_filtro ->> 'colectivo';
  v_curso      smallint;
  v_cuest      integer[];
  v_particion  text[];   -- claves que son partes de un total, por colectivo y en orden canónico
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
    else array['docente', 'antiguedad', 'departamento_equipo']
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

  -- Permisos de coordinación (§6): solo su etapa, sin personal.
  if v_perfil.rol = 'coordinacion' then
    if v_col = 'personal' then
      raise exception 'Sin acceso a los resultados de personal' using errcode = '42501';
    end if;
    if v_filtro ? 'etapa' and v_filtro ->> 'etapa' <> v_perfil.etapa then
      raise exception 'Sin acceso a la etapa %', v_filtro ->> 'etapa' using errcode = '42501';
    end if;
    v_filtro := v_filtro || jsonb_build_object('etapa', v_perfil.etapa);
  end if;

  -- Ámbito. En alumnos, cuestionario y etapa delimitan el conjunto (son totales grandes);
  -- en familias la etapa es una parte del total.
  select coalesce(array_agg(c.id order by c.id), '{}') into v_cuest
  from public.cuestionario c
  where c.curso_id = v_curso
    and c.colectivo = v_col
    and (v_col <> 'alumnos' or not v_filtro ? 'etapa' or c.etapa = v_filtro ->> 'etapa')
    and (v_col <> 'alumnos' or not v_filtro ? 'cuestionario' or c.codigo = v_filtro ->> 'cuestionario');
  if cardinality(v_cuest) = 0 then
    raise exception 'No hay datos para este filtro' using errcode = 'P0002';
  end if;

  -- Valores fijados de las claves de partición.
  foreach k in array v_particion loop
    continue when not v_filtro ? k;
    continue when v_col = 'alumnos' and k in ('cuestionario', 'etapa');
    v_fijos := v_fijos || jsonb_build_object(k, case
      when k = 'docente' and jsonb_typeof(v_filtro -> k) = 'boolean'
        then case when (v_filtro ->> k)::boolean then 'docente' else 'no_docente' end
      else v_filtro ->> k
    end);
  end loop;

  -- Dimensiones del cálculo en orden canónico.
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

-- Celdas y márgenes de una métrica sobre un conjunto de cuestionarios, sin suprimir.
-- Métricas (p_metrica):
--   {"tipo": "personas"}                          personas que respondieron
--   {"tipo": "satisfaccion"}                      media agrupada de los bloques que entran en media (escala de 1 a 6)
--   {"tipo": "bloque", "codigo": "profesorado"}   media agrupada de un bloque
--   {"tipo": "pregunta", "codigo": "..."}         una pregunta, con distribución
--   {"tipo": "recomendacion"}                     recomendación, con distribución y NPS
--   {"tipo": "seleccion", "codigo": "..."}        selección múltiple: personas que eligen cada opción
-- n es el número que decide la supresión: personas para conjuntos de preguntas,
-- valoraciones válidas para una pregunta (§3).
create function privado.celdas(p_cuest integer[], p_dims text[], p_metrica jsonb)
returns table (k1 text, k2 text, agg1 boolean, agg2 boolean, n integer, datos jsonb)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_tipo      text := p_metrica ->> 'tipo';
  v_cod       text := p_metrica ->> 'codigo';
  v_pregunta  public.pregunta;
  v_ndims     integer := coalesce(cardinality(p_dims), 0);
  v_asig      boolean := 'asignatura' = any(coalesce(p_dims, '{}'));
  e1          text := privado.expr_dim(p_dims[1]);
  e2          text := privado.expr_dim(p_dims[2]);
  v_from      text;
  v_where     text;
  v_n         text;
  v_datos     text;
  v_group     text;
  v_rec       boolean := false;
  v_dist_min  integer;
  v_dist_max  integer;
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
  if v_tipo = 'seleccion' and v_asig then
    raise exception 'La selección múltiple no se reparte por asignatura';
  end if;

  if v_tipo = 'seleccion' then
    v_from := 'privado.respuesta_opcion o
      join privado.respuesta r on r.id = o.respuesta_id
      join public.cuestionario c on c.id = r.cuestionario_id
      left join public.grupo g on g.id = r.grupo_id
      left join public.asignatura a on false';
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
      left join public.asignatura a on false';
    v_where := 'r.cuestionario_id = any($1)';
    v_n := 'count(distinct r.id)';
    v_datos := '''{}''::jsonb';

  else
    v_from := 'privado.respuesta_item i
      join privado.respuesta r on r.id = i.respuesta_id
      join public.cuestionario c on c.id = r.cuestionario_id
      left join public.grupo g on g.id = r.grupo_id
      left join public.asignatura a on a.id = i.asignatura_id
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

    -- NPS: % de 9 y 10 menos % de 6 o menos, igual en escalas de 0 a 10 y de 1 a 10 (§3).
    if v_rec then
      v_datos := v_datos || ' || jsonb_build_object(
        ''promotores_pct'', 100.0 * count(*) filter (where i.valor >= 9) / nullif(count(i.valor), 0),
        ''neutros_pct'', 100.0 * count(*) filter (where i.valor in (7, 8)) / nullif(count(i.valor), 0),
        ''detractores_pct'', 100.0 * count(*) filter (where i.valor <= 6) / nullif(count(i.valor), 0),
        ''nps'', 100.0 * (count(*) filter (where i.valor >= 9) - count(*) filter (where i.valor <= 6)) / nullif(count(i.valor), 0))';
    end if;
  end if;

  v_group := case v_ndims
    when 0 then ''
    when 1 then format('group by grouping sets ((%s), ())', e1)
    else format('group by grouping sets ((%1$s, %2$s), (%1$s), (%2$s), ())', e1, e2)
  end;

  return query execute format(
    'select %s, %s, %s, %s, (%s)::integer, %s from %s where %s %s order by 1 nulls first, 2 nulls first',
    coalesce(e1, 'null::text'),
    coalesce(e2, 'null::text'),
    case when e1 is null then 'true' else format('grouping(%s) = 1', e1) end,
    case when e2 is null then 'true' else format('grouping(%s) = 1', e2) end,
    v_n, v_datos, v_from, v_where, v_group)
  using p_cuest, v_cod, v_pregunta.id;
end $$;

-- Mínimo de 5 y supresión complementaria (§5). Recibe las filas de privado.celdas y
-- devuelve el motivo de supresión de cada una (null si es visible).
-- Una "línea" es un total y las partes que lo desagregan en una dimensión: el total
-- general con sus filas, el total general con sus columnas, cada fila con sus celdas y
-- cada columna con sus celdas. Si en una línea con total visible queda exactamente una
-- parte suprimida, se suprime también la parte visible más pequeña. Se repite hasta
-- que nada cambia, porque suprimir una celda puede dejar sola otra en su columna.
create function privado.suprimir(p_k1 text[], p_k2 text[], p_agg1 boolean[], p_agg2 boolean[], p_n integer[])
returns text[]
language plpgsql immutable set search_path = '' as $$
declare
  v_len      integer := coalesce(cardinality(p_n), 0);
  v_mot      text[] := array_fill(null::text, array[v_len]);
  v_cambio   boolean;
  v_cuenta   integer;
  v_mejor    integer;
  t integer; j integer; d integer;
  v_parte    boolean;
begin
  for j in 1 .. v_len loop
    if p_n[j] < 5 then
      v_mot[j] := 'menos_de_5';
    end if;
  end loop;

  loop
    v_cambio := false;
    for t in 1 .. v_len loop
      continue when v_mot[t] is not null;
      for d in 1 .. 2 loop
        v_cuenta := 0;
        v_mejor := null;
        for j in 1 .. v_len loop
          -- j es parte de la línea (t, d) si desagrega la dimensión d de t y coincide en la otra.
          v_parte := case d
            when 1 then p_agg1[t] and not p_agg1[j] and p_agg2[j] = p_agg2[t]
                        and (p_agg2[t] or p_k2[j] = p_k2[t])
            else        p_agg2[t] and not p_agg2[j] and p_agg1[j] = p_agg1[t]
                        and (p_agg1[t] or p_k1[j] = p_k1[t])
          end;
          continue when not v_parte;
          if v_mot[j] is not null then
            v_cuenta := v_cuenta + 1;
          elsif v_mejor is null
             or p_n[j] < p_n[v_mejor]
             or (p_n[j] = p_n[v_mejor]
                 and coalesce(p_k1[j], '') || '|' || coalesce(p_k2[j], '')
                   < coalesce(p_k1[v_mejor], '') || '|' || coalesce(p_k2[v_mejor], '')) then
            v_mejor := j;
          end if;
        end loop;
        if v_cuenta = 1 and v_mejor is not null then
          v_mot[v_mejor] := 'complementaria';
          v_cambio := true;
        end if;
      end loop;
    end loop;
    exit when not v_cambio;
  end loop;

  return v_mot;
end $$;

-- Fila de salida: visible con sus datos, o suprimida sin n, media ni distribución.
create function privado.fila(p_clave jsonb, p_motivo text, p_n integer, p_datos jsonb)
returns jsonb
language sql immutable set search_path = '' as $$
  select case when p_motivo is null
    then jsonb_build_object('clave', p_clave, 'suprimido', false, 'n', p_n) || coalesce(p_datos, '{}')
    else jsonb_build_object('clave', p_clave, 'suprimido', true, 'motivo', p_motivo)
  end;
$$;
