-- Detalle de cada pregunta por clase también en la versión docente del informe del profesor/a (petición de Mark del
-- 06/11/2026, especificación §7.2). En pantalla, en el PDF y en el enlace personal.
--
-- Cada celda (una pregunta en una clase) ya sale con el mínimo de 5 y la complementaria de su tabla (grupo por
-- asignatura del cuestionario, privado.clases). Al enseñar todas las preguntas de una clase junto a la media de la
-- clase, hace falta un paso más en la versión docente, porque la media de la clase es la media de todas sus
-- valoraciones y cada celda lleva su número de respuestas:
--   - si en una clase visible queda oculta una sola pregunta, se podría despejar restando las demás de la media de la
--     clase: se oculta también otra (la de menos respuestas), como complementaria;
--   - si la clase está oculta, se ocultan todas sus preguntas (con todas visibles, se recompondría su media).
-- La media de cada pregunta del docente se vuelve a calcular solo con las clases que quedan visibles.
-- La versión completa (Dirección y administración) no cambia.

create or replace function privado.complementaria_por_clase(p_bloque jsonb, p_preguntas jsonb)
returns jsonb
language plpgsql volatile set search_path = '' as $$
declare
  v_c          jsonb;
  v_x          jsonb;
  v_p          jsonb;
  v_codigos    text[];
  v_celdas     jsonb[];
  a_k text[]; a_g boolean[]; a_n integer[];
  v_mot        text[];
  v_ocultar    jsonb := '{}';   -- codigo de la pregunta -> lista de claves de clase que se ocultan
  v_salida     jsonb := '[]';
  v_nuevas     jsonb;
  v_ocultas    integer;
  v_suma numeric; v_nval integer; v_nper integer; v_vis integer;
  i integer;
begin
  for v_c in select x from jsonb_array_elements(p_bloque -> 'celdas') x loop
    v_codigos := '{}'; v_celdas := '{}';
    for v_p in select x from jsonb_array_elements(p_preguntas) x loop
      select y into v_x from jsonb_array_elements(v_p -> 'resultado' -> 'celdas') y where y -> 'clave' = v_c -> 'clave';
      continue when v_x is null;
      v_codigos := v_codigos || (v_p ->> 'codigo');
      v_celdas := v_celdas || v_x;
    end loop;
    continue when cardinality(v_codigos) = 0;

    if (v_c ->> 'suprimido')::boolean then
      v_mot := array_fill('complementaria'::text, array[cardinality(v_codigos) + 1]);
    else
      -- La clase como margen y sus preguntas como partes; lo ya oculto entra con 0 respuestas.
      a_k := array[null::text] || v_codigos;
      a_g := array[true] || array_fill(false, array[cardinality(v_codigos)]);
      a_n := array[(v_c ->> 'n')::integer];
      for i in 1 .. cardinality(v_celdas) loop
        a_n := a_n || case when (v_celdas[i] ->> 'suprimido')::boolean then 0 else (v_celdas[i] ->> 'n')::integer end;
      end loop;
      v_mot := privado.suprimir(a_k, array_fill(null::text, array[cardinality(a_n)]), a_g,
                                array_fill(true, array[cardinality(a_n)]), a_n);
    end if;

    for i in 1 .. cardinality(v_celdas) loop
      continue when (v_celdas[i] ->> 'suprimido')::boolean or v_mot[i + 1] is null;
      v_ocultar := jsonb_set(v_ocultar, array[v_codigos[i]],
                             coalesce(v_ocultar -> v_codigos[i], '[]') || jsonb_build_array(v_c -> 'clave'));
    end loop;
  end loop;

  for v_p in select x from jsonb_array_elements(p_preguntas) x loop
    if not v_ocultar ? (v_p ->> 'codigo') then
      v_salida := v_salida || v_p;
      continue;
    end if;
    v_nuevas := '[]'; v_ocultas := 0; v_suma := 0; v_nval := 0; v_nper := 0; v_vis := 0;
    for v_x in select y from jsonb_array_elements(v_p -> 'resultado' -> 'celdas') y loop
      if v_ocultar -> (v_p ->> 'codigo') @> jsonb_build_array(v_x -> 'clave') then
        v_x := privado.fila(v_x -> 'clave', 'complementaria', null, null)
               || jsonb_build_object('etapa', v_x -> 'etapa', 'tipo', v_x -> 'tipo', 'docentes_clase', v_x -> 'docentes_clase');
        if v_x ->> 'tipo' <> 'compartida' then v_ocultas := v_ocultas + 1; end if;
      elsif v_x ->> 'tipo' <> 'compartida' and not (v_x ->> 'suprimido')::boolean then
        v_vis := v_vis + 1;
        v_nper := v_nper + coalesce((v_x ->> 'n_personas')::integer, (v_x ->> 'n')::integer);
        v_nval := v_nval + coalesce((v_x ->> 'n_valoraciones')::integer, 0);
        v_suma := v_suma + coalesce((v_x ->> 'media')::numeric * (v_x ->> 'n_valoraciones')::integer, 0);
      end if;
      v_nuevas := v_nuevas || v_x;
    end loop;
    v_salida := v_salida || jsonb_set(v_p, '{resultado}', (v_p -> 'resultado') || jsonb_build_object(
      'celdas', v_nuevas,
      'combinaciones_excluidas', coalesce((v_p -> 'resultado' ->> 'combinaciones_excluidas')::integer, 0) + v_ocultas,
      'global', case when v_vis = 0
        then jsonb_build_object('suprimido', true, 'motivo', 'sin_combinaciones_visibles')
        else jsonb_build_object('suprimido', false, 'combinaciones', v_vis, 'n_personas_por_asignatura', v_nper,
                                'n_valoraciones', v_nval, 'media', case when v_nval > 0 then v_suma / v_nval end)
      end));
  end loop;
  return v_salida;
end $$;

revoke execute on function privado.complementaria_por_clase(jsonb, jsonb) from public, anon, authenticated;

-- Informe del profesor/a: igual que antes, con el paso por clase en la versión docente.
create or replace function privado.informe_profesor(p_curso smallint, p_docente integer, p_etapa text)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_bloque     jsonb := privado.resultados_profesor(p_curso, p_docente, '{"tipo": "bloque", "codigo": "profesorado"}', p_etapa);
  v_cuest      text[] := array(select distinct x -> 'clave' ->> 'cuestionario' from jsonb_array_elements(v_bloque -> 'celdas') x);
  v_preguntas  jsonb := '[]';
  v_p          record;
begin
  for v_p in
    select p.codigo_diccionario, p.texto_es, min(pc.orden) as orden
    from public.pregunta_cuestionario pc
    join public.bloque b on b.id = pc.bloque_id
    join public.pregunta p on p.id = pc.pregunta_id
    join public.cuestionario c on c.id = pc.cuestionario_id
    where c.curso_id = p_curso and b.codigo = 'profesorado' and c.codigo = any(v_cuest)
    group by p.codigo_diccionario, p.texto_es
    order by min(pc.orden), p.codigo_diccionario
  loop
    v_preguntas := v_preguntas || jsonb_build_object(
      'codigo', v_p.codigo_diccionario,
      'texto', v_p.texto_es,
      'resultado', privado.resultados_profesor(p_curso, p_docente,
                     jsonb_build_object('tipo', 'pregunta', 'codigo', v_p.codigo_diccionario), p_etapa));
  end loop;
  if not privado.ve_menos_de_5() then
    v_preguntas := privado.complementaria_por_clase(v_bloque, v_preguntas);
  end if;
  return v_bloque || jsonb_build_object('preguntas', v_preguntas,
    'version', case when privado.ve_menos_de_5() then 'completa' else 'docente' end);
end $$;

revoke execute on function privado.informe_profesor(smallint, integer, text) from public, anon, authenticated;

-- Resultados de una pregunta del profesorado con el criterio de la versión docente (la coordinación): los mismos que
-- en el informe, con el paso por clase.
create or replace function public.resultados_profesor(p_curso text, p_docente integer, p_metrica jsonb default '{"tipo": "bloque", "codigo": "profesorado"}')
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_perfil  public.usuario_perfil := permisos.exigir();
  v_curso   smallint := (select id from public.curso where nombre = p_curso);
  v_etapa   text;
  v_r       jsonb;
begin
  perform privado.exigir_metrica_publica(p_metrica);
  v_etapa := privado.etapa_para_docente(v_perfil, v_curso, p_docente);
  if not privado.ve_menos_de_5() and p_metrica = jsonb_build_object('tipo', 'pregunta', 'codigo', p_metrica ->> 'codigo') then
    select x -> 'resultado' into v_r
    from jsonb_array_elements(privado.informe_profesor(v_curso, p_docente, v_etapa) -> 'preguntas') x
    where x ->> 'codigo' = p_metrica ->> 'codigo';
    if v_r is not null then return v_r; end if;
  end if;
  return privado.resultados_profesor(v_curso, p_docente, p_metrica, v_etapa);
end $$;

-- Informe en pantalla (vista del profesor/a): el bloque, cada pregunta y cada pregunta en cada clase, en una sola
-- llamada y con la versión que corresponde al rol (la completa para Dirección y administración, la docente para la
-- coordinación). No es una descarga: no queda en el registro, igual que resultados_profesor.
create or replace function public.detalle_profesor(p_curso text, p_docente integer)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_perfil  public.usuario_perfil := permisos.exigir();
  v_curso   smallint := (select id from public.curso where nombre = p_curso);
  v_etapa   text;
begin
  v_etapa := privado.etapa_para_docente(v_perfil, v_curso, p_docente);
  return privado.informe_profesor(v_curso, p_docente, v_etapa);
end $$;

revoke execute on function public.detalle_profesor(text, integer) from public, anon;
grant execute on function public.detalle_profesor(text, integer) to authenticated;
