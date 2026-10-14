-- Informe completo de un profesor en una sola llamada (vista y PDF, §7.2): el bloque de
-- profesorado y cada una de sus preguntas, con los mismos permisos, mínimo de 5 y supresión
-- complementaria que resultados_profesor. Cada informe generado queda en el registro de
-- actividad (§7.5), indicando si forma parte de un lote.

create function public.informe_profesor(p_curso text, p_docente integer, p_lote boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_bloque     jsonb := public.resultados_profesor(p_curso, p_docente);
  v_cuest      text[] := array(select distinct c ->> 'cuestionario' from jsonb_array_elements(v_bloque -> 'celdas') x, lateral (select x -> 'clave' as c) y);
  v_preguntas  jsonb := '[]';
  v_p          record;
begin
  for v_p in
    select p.codigo_diccionario, p.texto_es, min(pc.orden) as orden
    from public.pregunta_cuestionario pc
    join public.bloque b on b.id = pc.bloque_id
    join public.pregunta p on p.id = pc.pregunta_id
    join public.cuestionario c on c.id = pc.cuestionario_id
    join public.curso cu on cu.id = c.curso_id
    where cu.nombre = p_curso and b.codigo = 'profesorado' and c.codigo = any(v_cuest)
    group by p.codigo_diccionario, p.texto_es
    order by min(pc.orden), p.codigo_diccionario
  loop
    v_preguntas := v_preguntas || jsonb_build_object(
      'codigo', v_p.codigo_diccionario,
      'texto', v_p.texto_es,
      'resultado', public.resultados_profesor(p_curso, p_docente,
                     jsonb_build_object('tipo', 'pregunta', 'codigo', v_p.codigo_diccionario)));
  end loop;

  perform privado.registrar('informe_profesor', jsonb_build_object('curso', p_curso, 'docente', p_docente, 'lote', p_lote));
  return v_bloque || jsonb_build_object('preguntas', v_preguntas);
end $$;

revoke execute on function public.informe_profesor(text, integer, boolean) from public, anon;
grant execute on function public.informe_profesor(text, integer, boolean) to authenticated;
