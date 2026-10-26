-- Coordinación de etapa en Familias (decisión del 26/10/2026): el resultado de las familias de todo el colegio como
-- referencia, junto al de su etapa (también cuando su etapa no llega a 5 y sus resultados están ocultos).
-- Solo el total del colegio: sin filtros ni repartos, que la coordinación sigue sin poder pedir fuera de su etapa.

CREATE OR REPLACE FUNCTION privado.resolver(p_filtro jsonb, p_dims text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      raise exception 'La referencia del colegio es solo el total de familias, sin filtros ni repartos';
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
end $function$;
