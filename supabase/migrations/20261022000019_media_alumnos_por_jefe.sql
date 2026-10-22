-- Decisión del 22/10/2026: Inglés y Adquisición de Lenguas funcionan como un único departamento
-- (un jefe), igual que Artes Visuales y Tecnología con Educación Física. En la base siguen los 9
-- cargos (uno por departamento oficial), pero el informe de cada jefe da una sola media de
-- alumnos: la media agrupada de todas las clases propias y atribuidas visibles de los docentes de
-- sus departamentos, con el mismo mínimo de 5 y la complementaria de la tabla de cada cuestionario
-- (privado.clases). Sin desglose por departamento oficial.

create function privado.media_alumnos_departamentos(p_curso text, p_departamentos text[])
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
  select id into v_curso from public.curso where nombre = p_curso;

  select array_agg(distinct pr.id) into v_docs
  from public.persona_responsable pr
  join public.departamento d on d.id = pr.departamento_id
  where d.curso_id = v_curso and d.nombre = any(p_departamentos)
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

create or replace function public.media_departamento_alumnos(p_curso text, p_departamento text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform permisos.exigir();
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a los informes de responsables' using errcode = '42501';
  end if;
  return privado.media_alumnos_departamentos(p_curso, array[p_departamento]);
end $$;

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
  v_alu      jsonb;
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

  -- Una sola media por jefe: todas las clases propias visibles de sus departamentos.
  v_alu := jsonb_build_object('departamentos', to_jsonb(v_deps),
                              'media', privado.media_alumnos_departamentos(p_curso, v_deps));

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

revoke execute on function privado.media_alumnos_departamentos(text, text[]) from public;
