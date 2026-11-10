-- Informe del profesor/a: encabezados y notas (petición de Mark del 10/11/2026).
--
-- La media de todo el profesorado de cada etapa (la referencia de las columnas «Media de PAI (todo el profesorado)»)
-- sale para todas las etapas en que el docente tiene clases con la pregunta, no solo para las que tienen alguna clase
-- visible. Antes, en la versión docente, si todas sus clases de una etapa quedaban ocultas en una pregunta, faltaba la
-- referencia de esa etapa y el informe enseñaba «·». La referencia es de todo el profesorado de la etapa: no depende
-- del docente ni de sus clases, y fuera de la versión completa sigue saliendo solo la media. La regla del Colegio
-- (no sale si la pregunta está en dos etapas) no cambia. Lo demás de la función, igual que en la migración 047.

CREATE OR REPLACE FUNCTION privado.resultados_profesor(p_curso smallint, p_docente integer, p_metrica jsonb, p_etapa text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_docente    public.persona_responsable;
  v_f          record;
  v_celdas     jsonb := '[]';
  v_suma       numeric := 0;
  v_nval       integer := 0;
  v_nper       integer := 0;
  v_visibles   integer := 0;
  v_excluidas  integer := 0;
  v_compartidas integer := 0;
  v_menos5     integer := 0;
  v_etapas     text[] := '{}';
  v_comp       jsonb := '{}';
  v_e          text;
  v_cmp        jsonb;
  v_completa   boolean := privado.ve_menos_de_5();
  v_global_doc jsonb;
  v_previo     text;
begin
  select * into v_docente from public.persona_responsable where id = p_docente;

  for v_f in select * from privado.clases(p_curso, array[p_docente], p_metrica, p_etapa) loop
    v_celdas := v_celdas || (privado.fila(
      jsonb_build_object('cuestionario', v_f.cuestionario, 'grupo', v_f.grupo, 'asignatura', v_f.asignatura),
      v_f.motivo, v_f.n, v_f.datos)
      || jsonb_build_object('etapa', v_f.etapa, 'tipo', v_f.tipo, 'docentes_clase', v_f.docentes_clase));

    if v_f.tipo = 'compartida' then
      v_compartidas := v_compartidas + 1;
    elsif v_f.motivo is null then
      v_visibles := v_visibles + 1;
      if v_f.n < 5 then v_menos5 := v_menos5 + 1; end if;
      v_nper := v_nper + coalesce((v_f.datos ->> 'n_personas')::integer, v_f.n);
      v_nval := v_nval + coalesce((v_f.datos ->> 'n_valoraciones')::integer, 0);
      v_suma := v_suma + coalesce((v_f.datos ->> 'media')::numeric * (v_f.datos ->> 'n_valoraciones')::integer, 0);
    else
      v_excluidas := v_excluidas + 1;
    end if;
    -- Referencia de todas las etapas en que tiene clases con esta métrica, también si en una todas quedan ocultas:
    -- es la media de todo el profesorado de la etapa y no depende del docente.
    if not v_f.etapa = any(v_etapas) then
      v_etapas := v_etapas || v_f.etapa;
    end if;
  end loop;

  foreach v_e in array v_etapas loop
    select privado.fila(jsonb_build_object('etapa', v_e), privado.motivo_minimo(x.n), x.n, x.datos)
      into v_cmp
    from privado.celdas(
      array(select c.id from public.cuestionario c where c.curso_id = p_curso and c.colectivo = 'alumnos' and c.etapa = v_e),
      '{}', p_metrica) x;
    v_comp := v_comp || jsonb_build_object(v_e, v_cmp);
  end loop;
  select privado.fila('{}', privado.motivo_minimo(x.n), x.n, x.datos)
    into v_cmp
  from privado.celdas(
    array(select c.id from public.cuestionario c where c.curso_id = p_curso and c.colectivo = 'alumnos'),
    '{}', p_metrica) x;
  -- 2. Fuera de la versión completa, el Colegio no sale si la métrica está en dos etapas (Colegio menos la propia daría
  -- la otra). Con una sola, el Colegio es la propia etapa.
  if v_completa or (select count(distinct c.etapa) from public.cuestionario c
                    join public.pregunta_cuestionario pc on pc.cuestionario_id = c.id
                    join public.pregunta p on p.id = pc.pregunta_id join public.bloque b on b.id = pc.bloque_id
                    where c.curso_id = p_curso and c.colectivo = 'alumnos'
                      and case p_metrica ->> 'tipo' when 'pregunta' then p.codigo_diccionario = p_metrica ->> 'codigo'
                                                    when 'bloque' then b.codigo = p_metrica ->> 'codigo' else true end) <> 2 then
    v_comp := v_comp || jsonb_build_object('colegio', v_cmp);
  end if;
  -- 2. Fuera de la versión completa, de la comparación solo la media.
  if not v_completa then
    select coalesce(jsonb_object_agg(k, (select jsonb_object_agg(e.key, e.value) from jsonb_each(v) e
                                        where e.key in ('clave', 'suprimido', 'motivo', 'media'))), '{}')
      into v_comp from jsonb_each(v_comp) x(k, v);
  end if;

  if v_completa then
    v_previo := current_setting('encuestas.version_docente', true);
    perform set_config('encuestas.version_docente', 'on', true);
    v_global_doc := privado.resultados_profesor(p_curso, p_docente, p_metrica, p_etapa) -> 'global';
    perform set_config('encuestas.version_docente', coalesce(v_previo, ''), true);
  end if;

  return jsonb_build_object(
    'docente', jsonb_build_object('id', v_docente.id, 'nombre', v_docente.nombre, 'apellidos', v_docente.apellidos,
                                  'situacion', v_docente.situacion),
    'metrica', p_metrica,
    'celdas', v_celdas,
    'global', case when v_visibles = 0
      then jsonb_build_object('suprimido', true, 'motivo', 'sin_combinaciones_visibles')
      else jsonb_build_object('suprimido', false,
             'combinaciones', v_visibles,
             'n_personas_por_asignatura', v_nper,
             'n_valoraciones', v_nval,
             'media', case when v_nval > 0 then v_suma / v_nval end)
           || case when v_menos5 > 0 then jsonb_build_object('menos_de_5', v_menos5) else '{}'::jsonb end
    end,
    'combinaciones_excluidas', v_excluidas,
    'compartidas', v_compartidas,
    'comparacion', v_comp
  ) || case when v_completa then jsonb_build_object('global_docente', v_global_doc) else '{}'::jsonb end;
end $function$;

revoke execute on function privado.resultados_profesor(smallint, integer, jsonb, text) from public, anon, authenticated;
