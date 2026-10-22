-- Un jefe cuyos departamentos no tienen ninguna clase propia (todas compartidas entre varios
-- profesores, como Música) no tiene media de alumnos, pero no por anonimato: motivo
-- «solo_compartidas», con su propio aviso en la vista y en el PDF.

create or replace function privado.media_alumnos_departamentos(p_curso text, p_departamentos text[])
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
  v_compartidas integer := 0;
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

  for v_f in select * from privado.clases(v_curso, v_docs, '{"tipo": "bloque", "codigo": "profesorado"}') loop
    if v_f.tipo = 'compartida' then
      v_compartidas := v_compartidas + 1;
    elsif v_f.motivo is null then
      v_visibles := v_visibles + 1;
      v_nval := v_nval + (v_f.datos ->> 'n_valoraciones')::integer;
      v_suma := v_suma + (v_f.datos ->> 'media')::numeric * (v_f.datos ->> 'n_valoraciones')::integer;
    else
      v_excluidas := v_excluidas + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'profesores', cardinality(v_docs),
    'global', case
                   -- Ninguna clase propia: no es una supresión por anonimato, sino que todas son compartidas.
                   when v_visibles = 0 and v_excluidas = 0 and v_compartidas > 0
                     then jsonb_build_object('suprimido', true, 'motivo', 'solo_compartidas')
                   when v_visibles = 0 then jsonb_build_object('suprimido', true, 'motivo', 'sin_combinaciones_visibles')
                   else jsonb_build_object('suprimido', false, 'combinaciones', v_visibles, 'n_valoraciones', v_nval,
                                           'media', v_suma / nullif(v_nval, 0)) end,
    'combinaciones_excluidas', v_excluidas);
end $$;
