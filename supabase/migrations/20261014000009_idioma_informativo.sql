-- El idioma NO es un filtro ni una dimensión (decisión del 14/10/2026). Los resultados de
-- personal van siempre unidos y ninguna RPC devuelve resultados por idioma; el recuento por
-- idioma es solo informativo, con cifras exactas, y queda fuera de la supresión (§5).
-- Se retira «idioma» de las claves de personal añadidas en la migración 8.

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


-- Recuento informativo de personas por idioma de origen en personal: «N en español · N en
-- inglés». Mismo criterio de persona que el resto (alguna respuesta válida). Solo recuentos:
-- no existe ningún resultado desagregado por idioma.
create function public.recuento_idiomas(p_curso text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_perfil public.usuario_perfil := permisos.exigir();
begin
  if v_perfil.rol = 'coordinacion' then
    raise exception 'Sin acceso a los resultados de personal' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_object_agg(idioma, n)
    from (
      select r.idioma_origen as idioma, count(*) as n
      from privado.respuesta r
      join public.cuestionario c on c.id = r.cuestionario_id
      join public.curso cu on cu.id = c.curso_id
      where cu.nombre = p_curso and c.colectivo = 'personal'
        and (exists (select 1 from privado.respuesta_item i where i.respuesta_id = r.id and i.valor is not null)
             or exists (select 1 from privado.respuesta_opcion o where o.respuesta_id = r.id))
      group by r.idioma_origen
    ) x
  ), '{}');
end $$;

revoke execute on function public.recuento_idiomas(text) from public, anon;
grant execute on function public.recuento_idiomas(text) to authenticated;
