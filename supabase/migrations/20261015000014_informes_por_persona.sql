-- Informes por persona dentro de Personal (§7.0 y §7.3):
--   * informe_responsable admite el tipo "centro" (valoración del centro por todo el personal),
--     que va en el nivel de Dirección junto a Superiores;
--   * media_departamento_alumnos: media de los profesores de un departamento según las
--     encuestas de alumnos. Como la media global del profesor (§5.3), solo usa las
--     combinaciones asignatura y grupo visibles en la tabla de su cuestionario: si sumara todas,
--     restando las visibles de sus profesores se deducirían las ocultas.
-- Solo administración y dirección.

create or replace function public.informe_responsable(p_curso text, p_tipo text, p_ambito text default null, p_registrar boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_filtro  jsonb := jsonb_build_object('curso', p_curso, 'colectivo', 'personal');
  v_bloque  text;
  v_dims    text[] := '{}';
  v_total   jsonb;
begin
  perform permisos.exigir();
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a los informes de responsables' using errcode = '42501';
  end if;

  if p_tipo = 'equipo_individualizacion' then
    v_bloque := 'equipo_individualizacion';
  elsif p_tipo = 'departamento' then
    if p_ambito is null then
      raise exception 'El informe de departamento necesita el departamento';
    end if;
    v_bloque := 'reuniones_departamento';
    v_filtro := v_filtro || jsonb_build_object('departamento', p_ambito);
  elsif p_tipo = 'centro' then
    v_bloque := 'centro';
  elsif p_tipo = 'superiores' then
    v_bloque := 'superiores';
    v_filtro := v_filtro || jsonb_build_object('docente', false);
  else
    raise exception 'Tipo de informe no válido: %', p_tipo;
  end if;

  v_total := public.resultados(v_filtro, jsonb_build_object('tipo', 'bloque', 'codigo', v_bloque), v_dims) -> 'total';

  if p_registrar then
    perform privado.registrar('informe_responsable', jsonb_build_object('curso', p_curso, 'tipo', p_tipo, 'ambito', p_ambito));
  end if;

  return jsonb_build_object(
    'tipo', p_tipo,
    'ambito', p_ambito,
    'bloque', v_bloque,
    'total', v_total,
    -- Si el conjunto está oculto, tampoco se detallan sus preguntas.
    'preguntas', case when (v_total ->> 'suprimido')::boolean then '[]'::jsonb
                      else public.detalle_preguntas(v_filtro, v_bloque, v_dims) end
  );
end $$;


create function public.media_departamento_alumnos(p_curso text, p_departamento text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_curso      smallint;
  v_profes     integer;
  v_cuest      record;
  a_k1 text[]; a_k2 text[]; a_g1 boolean[]; a_g2 boolean[]; a_n integer[]; a_d jsonb[];
  v_mot        text[];
  v_suma       numeric := 0;
  v_nval       integer := 0;
  v_visibles   integer := 0;
  v_excluidas  integer := 0;
  i integer;
begin
  perform permisos.exigir();
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a los informes de responsables' using errcode = '42501';
  end if;
  select id into v_curso from public.curso where nombre = p_curso;

  select count(distinct ad.docente_id) into v_profes
  from public.asignacion_docente ad
  join public.persona_responsable pr on pr.id = ad.docente_id
  join public.departamento d on d.id = pr.departamento_id
  where ad.curso_id = v_curso and d.nombre = p_departamento;

  if coalesce(v_profes, 0) = 0 then
    return jsonb_build_object('profesores', 0,
      'global', jsonb_build_object('suprimido', true, 'motivo', 'sin_asignacion'), 'combinaciones_excluidas', 0);
  end if;

  for v_cuest in
    select distinct c.id
    from public.asignacion_docente ad
    join public.persona_responsable pr on pr.id = ad.docente_id
    join public.departamento d on d.id = pr.departamento_id
    join public.grupo g on g.id = ad.grupo_id
    join public.cuestionario c on c.curso_id = ad.curso_id and c.colectivo = 'alumnos' and c.etapa = g.etapa
    where ad.curso_id = v_curso and d.nombre = p_departamento
      and exists (select 1 from privado.respuesta r where r.cuestionario_id = c.id and r.grupo_id = g.id)
  loop
    select array_agg(x.k1), array_agg(x.k2), array_agg(x.agg1), array_agg(x.agg2), array_agg(x.n), array_agg(x.datos)
      into a_k1, a_k2, a_g1, a_g2, a_n, a_d
    from privado.celdas(array[v_cuest.id], array['grupo', 'asignatura'], '{"tipo": "bloque", "codigo": "profesorado"}') x;
    v_mot := privado.suprimir(a_k1, a_k2, a_g1, a_g2, a_n);

    for i in 1 .. coalesce(cardinality(a_n), 0) loop
      continue when a_g1[i] or a_g2[i];
      -- Cada combinación cuenta una vez aunque la compartan dos docentes del departamento.
      continue when not exists (
        select 1 from public.asignacion_docente ad
        join public.persona_responsable pr on pr.id = ad.docente_id
        join public.departamento d on d.id = pr.departamento_id
        join public.grupo g on g.id = ad.grupo_id
        join public.asignatura a on a.id = ad.asignatura_id
        where ad.curso_id = v_curso and d.nombre = p_departamento and g.nombre = a_k1[i] and a.nombre = a_k2[i]);
      if v_mot[i] is null then
        v_visibles := v_visibles + 1;
        v_nval := v_nval + (a_d[i] ->> 'n_valoraciones')::integer;
        v_suma := v_suma + (a_d[i] ->> 'media')::numeric * (a_d[i] ->> 'n_valoraciones')::integer;
      else
        v_excluidas := v_excluidas + 1;
      end if;
    end loop;
  end loop;

  return jsonb_build_object(
    'profesores', v_profes,
    'global', case when v_visibles = 0 then jsonb_build_object('suprimido', true, 'motivo', 'sin_combinaciones_visibles')
                   else jsonb_build_object('suprimido', false, 'combinaciones', v_visibles, 'n_valoraciones', v_nval,
                                           'media', v_suma / v_nval) end,
    'combinaciones_excluidas', v_excluidas);
end $$;

revoke execute on function public.media_departamento_alumnos(text, text) from public, anon;
grant execute on function public.media_departamento_alumnos(text, text) to authenticated;
