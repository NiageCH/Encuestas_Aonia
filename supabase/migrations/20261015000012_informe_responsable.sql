-- Informes de responsables (§7.3), por ámbito y no por persona (no hay lista de jefes):
--   equipo_individualizacion · bloque del Equipo de Individualización (lo contestan los tutores)
--   departamento             · reuniones de departamento de un departamento (p_ambito)
--   superiores               · bloque Superiores; en 2025/26 solo lo contestó el personal no docente
-- Solo administración y dirección. Usa las mismas RPC que las vistas (mínimo de 5 y supresión
-- complementaria). Si p_registrar, la generación queda en el registro de actividad (PDF).

create function public.informe_responsable(p_curso text, p_tipo text, p_ambito text default null, p_registrar boolean default false)
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

revoke execute on function public.informe_responsable(text, text, text, boolean) from public, anon;
grant execute on function public.informe_responsable(text, text, text, boolean) to authenticated;
