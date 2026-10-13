-- RPC públicas de resultados. Todas aplican permisos, el mínimo de 5 y la supresión
-- complementaria. Devuelven valores sin redondear (§3); el redondeo es cosa de la vista.

-- Resultado de una métrica para un filtro, opcionalmente repartido en dimensiones.
--   p_filtro:      {"curso": "2025/26", "colectivo": "alumnos", "cuestionario": "...",
--                   "etapa": "...", "grupo": "Y9 A", "asignatura": "...",
--                   "docente": true, "antiguedad": "primer_ano", "departamento_equipo": "..."}
--   p_metrica:     ver privado.celdas
--   p_dimensiones: reparto pedido, por ejemplo {grupo} o {grupo,asignatura}
-- Devuelve {total, partes[]}. Cada fila lleva su clave y, si está suprimida, solo el motivo
-- ("menos_de_5", "complementaria" o "sin_datos").
create function public.resultados(p_filtro jsonb, p_metrica jsonb, p_dimensiones text[] default '{}')
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_res     jsonb := privado.resolver(p_filtro, p_dimensiones);
  v_dims    text[] := array(select jsonb_array_elements_text(v_res -> 'dims'));
  v_fijos   jsonb := v_res -> 'fijos';
  v_cuest   integer[] := array(select jsonb_array_elements_text(v_res -> 'cuestionarios')::integer);
  a_k1 text[]; a_k2 text[]; a_g1 boolean[]; a_g2 boolean[]; a_n integer[]; a_d jsonb[];
  v_mot     text[];
  v_total   jsonb;
  v_partes  jsonb := '[]';
  v_clave   jsonb;
  v_ok      boolean;
  v_es_total boolean;
  v_k       text;
  v_agg     boolean;
  i integer; d integer;
begin
  select array_agg(c.k1), array_agg(c.k2), array_agg(c.agg1), array_agg(c.agg2), array_agg(c.n), array_agg(c.datos)
    into a_k1, a_k2, a_g1, a_g2, a_n, a_d
  from privado.celdas(v_cuest, v_dims, p_metrica) c;

  v_mot := privado.suprimir(a_k1, a_k2, a_g1, a_g2, a_n);

  for i in 1 .. coalesce(cardinality(a_n), 0) loop
    v_ok := true;
    v_es_total := true;
    v_clave := v_fijos;
    for d in 1 .. cardinality(v_dims) loop
      v_k := case d when 1 then a_k1[i] else a_k2[i] end;
      v_agg := case d when 1 then a_g1[i] else a_g2[i] end;
      if v_fijos ? v_dims[d] then
        v_ok := v_ok and not v_agg and v_k = v_fijos ->> v_dims[d];
      elsif not v_agg then
        v_es_total := false;
        v_clave := v_clave || jsonb_build_object(v_dims[d], v_k);
      end if;
    end loop;
    continue when not v_ok;

    if v_es_total then
      v_total := privado.fila(v_clave, v_mot[i], a_n[i], a_d[i]);
    else
      v_partes := v_partes || privado.fila(v_clave, v_mot[i], a_n[i], a_d[i]);
    end if;
  end loop;

  return jsonb_build_object(
    'metrica', p_metrica,
    'dimensiones', v_res -> 'salida',
    'total', coalesce(v_total, privado.fila(v_fijos, 'sin_datos', null, null)),
    'partes', v_partes
  );
end $$;

-- Indicadores de un filtro: personas, satisfacción media y recomendación.
create function public.resumen(p_filtro jsonb)
returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'personas',      public.resultados(p_filtro, '{"tipo": "personas"}') -> 'total',
    'satisfaccion',  public.resultados(p_filtro, '{"tipo": "satisfaccion"}') -> 'total',
    'recomendacion', public.resultados(p_filtro, '{"tipo": "recomendacion"}') -> 'total'
  );
$$;

-- Detalle por pregunta de un bloque (por código), en el orden del cuestionario.
create function public.detalle_preguntas(p_filtro jsonb, p_bloque text, p_dimensiones text[] default '{}')
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_res    jsonb := privado.resolver(p_filtro, p_dimensiones);
  v_cuest  integer[] := array(select jsonb_array_elements_text(v_res -> 'cuestionarios')::integer);
  v_salida jsonb := '[]';
  v_p      record;
begin
  for v_p in
    select p.codigo_diccionario, p.texto_es, p.tipo
    from public.pregunta_cuestionario pc
    join public.bloque b on b.id = pc.bloque_id
    join public.pregunta p on p.id = pc.pregunta_id
    where pc.cuestionario_id = any(v_cuest) and b.codigo = p_bloque and p.tipo <> 'seleccion_multiple'
    group by p.codigo_diccionario, p.texto_es, p.tipo
    order by min(b.orden), min(pc.orden), p.codigo_diccionario
  loop
    v_salida := v_salida || jsonb_build_object(
      'codigo', v_p.codigo_diccionario,
      'texto', v_p.texto_es,
      'resultado', public.resultados(p_filtro,
        jsonb_build_object('tipo', 'pregunta', 'codigo', v_p.codigo_diccionario), p_dimensiones));
  end loop;
  return v_salida;
end $$;

-- Profesores con docencia en el curso. La coordinación solo ve los de su etapa.
create function public.listar_profesores(p_curso text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_perfil public.usuario_perfil := permisos.exigir();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', pr.id, 'nombre', pr.nombre, 'apellidos', pr.apellidos,
             'departamento', dep.nombre)
           order by pr.apellidos, pr.nombre)
    from public.persona_responsable pr
    left join public.departamento dep on dep.id = pr.departamento_id
    where exists (
      select 1
      from public.asignacion_docente ad
      join public.curso cu on cu.id = ad.curso_id
      join public.grupo g on g.id = ad.grupo_id
      where ad.docente_id = pr.id
        and cu.nombre = p_curso
        and (v_perfil.rol <> 'coordinacion' or g.etapa = v_perfil.etapa))
  ), '[]');
end $$;

-- Resultados de un profesor en las encuestas de alumnos (§7.2 y §5.3).
-- Cada combinación asignatura y grupo toma su estado de la tabla asignatura por grupo de
-- su cuestionario, la misma que ve dirección: lo que allí está suprimido aquí también.
-- La media global se calcula solo con las combinaciones visibles.
create function public.resultados_profesor(
  p_curso text,
  p_docente integer,
  p_metrica jsonb default '{"tipo": "bloque", "codigo": "profesorado"}'
)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_perfil     public.usuario_perfil := permisos.exigir();
  v_curso      smallint;
  v_docente    public.persona_responsable;
  v_cuest      record;
  a_k1 text[]; a_k2 text[]; a_g1 boolean[]; a_g2 boolean[]; a_n integer[]; a_d jsonb[];
  v_mot        text[];
  v_celdas     jsonb := '[]';
  v_suma       numeric := 0;
  v_nval       integer := 0;
  v_nper       integer := 0;
  v_visibles   integer := 0;
  v_excluidas  integer := 0;
  v_etapas     text[] := '{}';
  v_comp       jsonb := '{}';
  v_e          text;
  v_cmp        jsonb;
  i integer;
begin
  select id into v_curso from public.curso where nombre = p_curso;
  select * into v_docente from public.persona_responsable where id = p_docente;
  if v_curso is null or v_docente.id is null then
    raise exception 'Profesor o curso no encontrado' using errcode = 'P0002';
  end if;

  if v_perfil.rol = 'coordinacion' and not exists (
    select 1 from public.asignacion_docente ad join public.grupo g on g.id = ad.grupo_id
    where ad.docente_id = p_docente and ad.curso_id = v_curso and g.etapa = v_perfil.etapa
  ) then
    raise exception 'Sin acceso a este profesor' using errcode = '42501';
  end if;

  -- Cuestionarios de alumnos que contienen grupos del profesor.
  for v_cuest in
    select distinct c.id, c.codigo, c.etapa
    from public.asignacion_docente ad
    join public.grupo g on g.id = ad.grupo_id
    join public.cuestionario c on c.curso_id = ad.curso_id and c.colectivo = 'alumnos' and c.etapa = g.etapa
    where ad.docente_id = p_docente and ad.curso_id = v_curso
      and (v_perfil.rol <> 'coordinacion' or g.etapa = v_perfil.etapa)
      and exists (select 1 from privado.respuesta r where r.cuestionario_id = c.id and r.grupo_id = g.id)
    order by c.id
  loop
    select array_agg(x.k1), array_agg(x.k2), array_agg(x.agg1), array_agg(x.agg2), array_agg(x.n), array_agg(x.datos)
      into a_k1, a_k2, a_g1, a_g2, a_n, a_d
    from privado.celdas(array[v_cuest.id], array['grupo', 'asignatura'], p_metrica) x;
    v_mot := privado.suprimir(a_k1, a_k2, a_g1, a_g2, a_n);

    for i in 1 .. coalesce(cardinality(a_n), 0) loop
      continue when a_g1[i] or a_g2[i];
      continue when not exists (
        select 1 from public.asignacion_docente ad
        join public.grupo g on g.id = ad.grupo_id
        join public.asignatura a on a.id = ad.asignatura_id
        where ad.docente_id = p_docente and ad.curso_id = v_curso
          and g.nombre = a_k1[i] and a.nombre = a_k2[i]);

      v_celdas := v_celdas || (privado.fila(
        jsonb_build_object('cuestionario', v_cuest.codigo, 'grupo', a_k1[i], 'asignatura', a_k2[i]),
        v_mot[i], a_n[i], a_d[i]) || jsonb_build_object('etapa', v_cuest.etapa));

      if v_mot[i] is null then
        v_visibles := v_visibles + 1;
        v_nper := v_nper + coalesce((a_d[i] ->> 'n_personas')::integer, a_n[i]);
        v_nval := v_nval + coalesce((a_d[i] ->> 'n_valoraciones')::integer, 0);
        v_suma := v_suma + coalesce((a_d[i] ->> 'media')::numeric * (a_d[i] ->> 'n_valoraciones')::integer, 0);
        if not v_cuest.etapa = any(v_etapas) then
          v_etapas := v_etapas || v_cuest.etapa;
        end if;
      else
        v_excluidas := v_excluidas + 1;
      end if;
    end loop;
  end loop;

  -- Comparación con la media de cada etapa en la que tiene resultados visibles y, salvo
  -- para coordinación (que solo ve su etapa), con la del colegio.
  foreach v_e in array v_etapas loop
    select privado.fila(jsonb_build_object('etapa', v_e), case when x.n < 5 then 'menos_de_5' end, x.n, x.datos)
      into v_cmp
    from privado.celdas(
      array(select c.id from public.cuestionario c where c.curso_id = v_curso and c.colectivo = 'alumnos' and c.etapa = v_e),
      '{}', p_metrica) x;
    v_comp := v_comp || jsonb_build_object(v_e, v_cmp);
  end loop;
  if v_perfil.rol <> 'coordinacion' then
    select privado.fila('{}', case when x.n < 5 then 'menos_de_5' end, x.n, x.datos)
      into v_cmp
    from privado.celdas(
      array(select c.id from public.cuestionario c where c.curso_id = v_curso and c.colectivo = 'alumnos'),
      '{}', p_metrica) x;
    v_comp := v_comp || jsonb_build_object('colegio', v_cmp);
  end if;

  return jsonb_build_object(
    'docente', jsonb_build_object('id', v_docente.id, 'nombre', v_docente.nombre, 'apellidos', v_docente.apellidos),
    'metrica', p_metrica,
    'celdas', v_celdas,
    'global', case when v_visibles = 0
      then jsonb_build_object('suprimido', true, 'motivo', 'sin_combinaciones_visibles')
      else jsonb_build_object('suprimido', false,
             'combinaciones', v_visibles,
             'n_personas_por_asignatura', v_nper,
             'n_valoraciones', v_nval,
             'media', case when v_nval > 0 then v_suma / v_nval end)
    end,
    'combinaciones_excluidas', v_excluidas,
    'comparacion', v_comp
  );
end $$;

revoke execute on function public.resultados(jsonb, jsonb, text[]) from public, anon;
revoke execute on function public.resumen(jsonb) from public, anon;
revoke execute on function public.detalle_preguntas(jsonb, text, text[]) from public, anon;
revoke execute on function public.listar_profesores(text) from public, anon;
revoke execute on function public.resultados_profesor(text, integer, jsonb) from public, anon;

grant execute on function public.resultados(jsonb, jsonb, text[]) to authenticated;
grant execute on function public.resumen(jsonb) to authenticated;
grant execute on function public.detalle_preguntas(jsonb, text, text[]) to authenticated;
grant execute on function public.listar_profesores(text) to authenticated;
grant execute on function public.resultados_profesor(text, integer, jsonb) to authenticated;
