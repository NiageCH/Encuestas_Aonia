-- Criterio de anonimato confirmado por escrito por Mark (especificación §5.0):
--   - Dirección y administración ven todos los resultados, también los de menos de 5 respuestas, con la marca
--     «menos de 5» y su número de respuestas, y sin supresión complementaria.
--   - La coordinación y la versión docente del informe del profesor/a siguen con el mínimo de 5 y la complementaria.
--
-- Todo el anonimato pasa por privado.suprimir y privado.fila, así que el criterio se decide en un solo sitio:
-- privado.ve_menos_de_5(). La versión docente la piden informe_profesor (p_version = 'docente') y el enlace personal
-- del docente, poniendo encuestas.version_docente = 'on' mientras se calcula. Ese ajuste solo puede endurecer el
-- criterio: sin el rol de Dirección o administración no se ve nada de menos de 5, valga lo que valga.

create or replace function privado.ve_menos_de_5() returns boolean
language sql volatile security definer set search_path = '' as $$
  select coalesce(current_setting('encuestas.version_docente', true), '') <> 'on'
     and coalesce((select p.rol in ('direccion', 'administrador') from permisos.perfil() p where p.id is not null), false);
$$;

-- Motivo de supresión de un resultado suelto (sin partes): «menos_de_5» solo cuando se aplica el mínimo.
create or replace function privado.motivo_minimo(p_n integer) returns text
language sql volatile set search_path = '' as $$
  select case when coalesce(p_n, 0) < 5 and not privado.ve_menos_de_5() then 'menos_de_5'
              when coalesce(p_n, 0) = 0 then 'sin_datos' end;
$$;

-- Mínimo de respuestas para entrar en una lista (aspectos con mayor y menor valoración).
create or replace function privado.minimo() returns integer
language sql volatile set search_path = '' as $$
  select case when privado.ve_menos_de_5() then 1 else 5 end;
$$;

-- Mínimo de 5 y supresión complementaria (§5). Igual que antes, salvo para Dirección y administración (fuera de la
-- versión docente): no se suprime nada y la marca «menos de 5» la pone privado.fila.
create or replace function privado.suprimir(p_k1 text[], p_k2 text[], p_agg1 boolean[], p_agg2 boolean[], p_n integer[])
returns text[]
language plpgsql volatile set search_path = '' as $$
declare
  v_len      integer := coalesce(cardinality(p_n), 0);
  v_mot      text[] := array_fill(null::text, array[v_len]);
  v_cambio   boolean;
  v_cuenta   integer;
  v_mejor    integer;
  t integer; j integer; d integer;
  v_parte    boolean;
begin
  if privado.ve_menos_de_5() then
    return v_mot;
  end if;

  for j in 1 .. v_len loop
    if p_n[j] < 5 then
      v_mot[j] := 'menos_de_5';
    end if;
  end loop;

  loop
    v_cambio := false;
    for t in 1 .. v_len loop
      continue when v_mot[t] is not null;
      for d in 1 .. 2 loop
        v_cuenta := 0;
        v_mejor := null;
        for j in 1 .. v_len loop
          v_parte := case d
            when 1 then p_agg1[t] and not p_agg1[j] and p_agg2[j] = p_agg2[t]
                        and (p_agg2[t] or p_k2[j] = p_k2[t])
            else        p_agg2[t] and not p_agg2[j] and p_agg1[j] = p_agg1[t]
                        and (p_agg1[t] or p_k1[j] = p_k1[t])
          end;
          continue when not v_parte;
          if v_mot[j] is not null then
            v_cuenta := v_cuenta + 1;
          elsif v_mejor is null
             or p_n[j] < p_n[v_mejor]
             or (p_n[j] = p_n[v_mejor]
                 and coalesce(p_k1[j], '') || '|' || coalesce(p_k2[j], '')
                   < coalesce(p_k1[v_mejor], '') || '|' || coalesce(p_k2[v_mejor], '')) then
            v_mejor := j;
          end if;
        end loop;
        if v_cuenta = 1 and v_mejor is not null then
          v_mot[v_mejor] := 'complementaria';
          v_cambio := true;
        end if;
      end loop;
    end loop;
    exit when not v_cambio;
  end loop;

  return v_mot;
end $$;

-- Fila de salida. Visible con menos de 5 respuestas solo puede darse para Dirección y administración: lleva la marca
-- «menos_de_5»: true, que la vista, el CSV y el PDF enseñan junto al número de respuestas.
create or replace function privado.fila(p_clave jsonb, p_motivo text, p_n integer, p_datos jsonb)
returns jsonb
language sql immutable set search_path = '' as $$
  select case when p_motivo is null
    then jsonb_build_object('clave', p_clave, 'suprimido', false, 'n', p_n) || coalesce(p_datos, '{}')
         || case when p_n < 5 then '{"menos_de_5": true}'::jsonb else '{}'::jsonb end
    else jsonb_build_object('clave', p_clave, 'suprimido', true, 'motivo', p_motivo)
  end;
$$;

-- Partes de un responsable juntas (§5.15): el resultado del conjunto con el mínimo según el rol.
create or replace function privado.conjunto(p_cuest integer[], p_dim text, p_valores text[], p_metrica jsonb)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  a_k1 text[]; a_k2 text[]; a_g1 boolean[]; a_g2 boolean[]; a_n integer[]; a_d jsonb[];
  v_mot      text[];
  v_vis      integer := 0;
  v_ocu      integer := 0;
  v_n        integer;
  v_datos    jsonb;
  i integer;
begin
  if p_dim not in ('tramo', 'departamento') then
    raise exception 'Dimensión no válida para un conjunto: %', p_dim;
  end if;
  select array_agg(x.k1), array_agg(x.k2), array_agg(x.agg1), array_agg(x.agg2), array_agg(x.n), array_agg(x.datos)
    into a_k1, a_k2, a_g1, a_g2, a_n, a_d
  from privado.celdas(p_cuest, array[p_dim], p_metrica) x;
  v_mot := privado.suprimir(a_k1, a_k2, a_g1, a_g2, a_n);
  for i in 1 .. coalesce(cardinality(a_n), 0) loop
    continue when a_g1[i] or not a_k1[i] = any(p_valores);
    if v_mot[i] is null then v_vis := v_vis + 1; else v_ocu := v_ocu + 1; end if;
  end loop;

  if v_vis + v_ocu = 0 then
    return privado.fila('{}', 'sin_datos', null, null);
  end if;
  if v_vis > 0 and v_ocu > 0 then
    return privado.fila('{}', 'complementaria', null, null);
  end if;

  select x.n, x.datos into v_n, v_datos
  from privado.celdas(p_cuest, '{}', p_metrica || jsonb_build_object(
         case p_dim when 'tramo' then 'tramos' else 'departamentos' end, to_jsonb(p_valores))) x;
  return privado.fila('{}', privado.motivo_minimo(v_n), v_n, v_datos);
end $$;

-- Resultados de un profesor/a, sin comprobar permisos (los comprueban quienes la llaman). p_etapa limita a una etapa
-- (coordinación). Con el criterio de Dirección añade «global_docente»: la media global tal como sale en la versión
-- docente, para que se puedan comparar las dos versiones del informe.
create or replace function privado.resultados_profesor(p_curso smallint, p_docente integer, p_metrica jsonb, p_etapa text)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
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
    if v_f.motivo is null and not v_f.etapa = any(v_etapas) then
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
  v_comp := v_comp || jsonb_build_object('colegio', v_cmp);

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
end $$;

revoke execute on function privado.resultados_profesor(smallint, integer, jsonb, text) from public, anon, authenticated;

-- Permisos para ver a un docente: la coordinación, solo a quien da clase en su etapa. Devuelve la etapa a la que se
-- limita (null para Dirección y administración).
create or replace function privado.etapa_para_docente(p_perfil public.usuario_perfil, p_curso smallint, p_docente integer)
returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_curso is null or not exists (select 1 from public.persona_responsable where id = p_docente) then
    raise exception 'Profesor/a o curso no encontrado' using errcode = 'P0002';
  end if;
  if p_perfil.rol <> 'coordinacion' then
    return null;
  end if;
  if not exists (
    select 1 from public.asignacion_docente ad join public.grupo g on g.id = ad.grupo_id
    where ad.docente_id = p_docente and ad.curso_id = p_curso and g.etapa = p_perfil.etapa
  ) and not exists (
    select 1 from privado.respuesta_docente rd join privado.respuesta r on r.id = rd.respuesta_id
    join public.cuestionario c on c.id = r.cuestionario_id
    where rd.docente_id = p_docente and c.curso_id = p_curso and c.etapa = p_perfil.etapa
  ) then
    raise exception 'Sin acceso a este profesor/a' using errcode = '42501';
  end if;
  return p_perfil.etapa;
end $$;

revoke execute on function privado.etapa_para_docente(public.usuario_perfil, smallint, integer) from public, anon, authenticated;

create or replace function public.resultados_profesor(p_curso text, p_docente integer, p_metrica jsonb default '{"tipo": "bloque", "codigo": "profesorado"}')
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_perfil  public.usuario_perfil := permisos.exigir();
  v_curso   smallint := (select id from public.curso where nombre = p_curso);
  v_etapa   text;
begin
  perform privado.exigir_metrica_publica(p_metrica);
  v_etapa := privado.etapa_para_docente(v_perfil, v_curso, p_docente);
  return privado.resultados_profesor(v_curso, p_docente, p_metrica, v_etapa);
end $$;

-- Informe del profesor/a: el bloque, cada pregunta y, dentro de cada pregunta, cada clase. Dos versiones:
--   completa: la de Dirección y administración (todo, con la marca «menos de 5»);
--   docente:  la que recibe el docente (mínimo de 5 y complementaria), igual que hasta ahora.
-- La coordinación siempre recibe la docente. Devuelve la versión que ha salido.
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
  return v_bloque || jsonb_build_object('preguntas', v_preguntas,
    'version', case when privado.ve_menos_de_5() then 'completa' else 'docente' end);
end $$;

revoke execute on function privado.informe_profesor(smallint, integer, text) from public, anon, authenticated;

drop function if exists public.informe_profesor(text, integer, boolean);
create or replace function public.informe_profesor(p_curso text, p_docente integer, p_lote boolean default false, p_version text default 'completa')
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_perfil  public.usuario_perfil := permisos.exigir();
  v_curso   smallint;
  v_etapa   text;
  v_previo  text := current_setting('encuestas.version_docente', true);
  v_informe jsonb;
begin
  if p_version is null or p_version not in ('completa', 'docente') then
    raise exception 'Versión del informe no válida' using errcode = '22023';
  end if;
  -- Permisos y etapa de la coordinación: los mismos que la vista.
  select id into v_curso from public.curso where nombre = p_curso;
  v_etapa := privado.etapa_para_docente(v_perfil, v_curso, p_docente);

  if p_version = 'docente' then
    perform set_config('encuestas.version_docente', 'on', true);
  end if;
  v_informe := privado.informe_profesor(v_curso, p_docente, v_etapa);
  perform set_config('encuestas.version_docente', coalesce(v_previo, ''), true);

  perform privado.registrar('informe_profesor', jsonb_build_object('curso', p_curso, 'docente', p_docente, 'lote', p_lote,
    'version', v_informe ->> 'version'));
  return v_informe;
end $$;

revoke execute on function public.informe_profesor(text, integer, boolean, text) from public, anon;
grant execute on function public.informe_profesor(text, integer, boolean, text) to authenticated;

-- Aspectos con mayor y menor valoración: con el criterio de Dirección entran también las preguntas con menos de 5
-- valoraciones (con su número, para marcarlas).
create or replace function public.puntos_colectivo(p_filtro jsonb, p_cuantos integer default 5)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_res    jsonb := privado.resolver(p_filtro, '{}');
  v_cuest  integer[] := array(select jsonb_array_elements_text(v_res -> 'cuestionarios')::integer);
  v_etapa  text := v_res -> 'fijos' ->> 'etapa';
  v_minimo integer := privado.minimo();
  v_filas  jsonb;
begin
  if exists (select 1 from jsonb_object_keys(v_res -> 'fijos') k where k <> 'etapa') then
    raise exception 'Los puntos fuertes y de mejora son del total del colectivo, sin filtros';
  end if;
  select coalesce(jsonb_agg(x order by x ->> 'media'), '[]') into v_filas
  from (
    select jsonb_build_object('codigo', p.codigo_diccionario, 'texto', p.texto_es, 'n', count(i.valor),
             'media', avg(i.valor), 'pct_bajo', 100.0 * count(*) filter (where i.valor <= 3) / count(i.valor)) as x
    from privado.respuesta_item i
    join privado.respuesta r on r.id = i.respuesta_id
    join public.pregunta p on p.id = i.pregunta_id
    join public.pregunta_cuestionario pc on pc.cuestionario_id = r.cuestionario_id and pc.pregunta_id = i.pregunta_id
    where r.cuestionario_id = any(v_cuest)
      and p.tipo = 'escala' and p.escala_min = 1 and p.escala_max = 6 and not pc.por_departamento
      and i.valor is not null
      and (v_etapa is null or exists (select 1 from privado.respuesta_etapa re where re.respuesta_id = r.id and re.etapa = v_etapa))
    group by p.codigo_diccionario, p.texto_es
    having count(i.valor) >= v_minimo
  ) t;
  return jsonb_build_object(
    'mejora', coalesce((select jsonb_agg(e order by (e ->> 'media')::numeric, (e ->> 'pct_bajo')::numeric desc)
                        from (select e from jsonb_array_elements(v_filas) e order by (e ->> 'media')::numeric, (e ->> 'pct_bajo')::numeric desc limit p_cuantos) z), '[]'),
    'fuertes', coalesce((select jsonb_agg(e order by (e ->> 'media')::numeric desc, (e ->> 'pct_bajo')::numeric)
                        from (select e from jsonb_array_elements(v_filas) e order by (e ->> 'media')::numeric desc, (e ->> 'pct_bajo')::numeric limit p_cuantos) z), '[]'));
end $$;

-- Media del profesorado de una jefatura según el alumnado: con el criterio de Dirección dice cuántas clases de menos de 5
-- incluye.
create or replace function privado.media_alumnos_departamentos(p_curso text, p_departamentos text[])
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_curso      smallint;
  v_docs       integer[];
  v_f          record;
  v_suma       numeric := 0;
  v_nval       integer := 0;
  v_visibles   integer := 0;
  v_excluidas  integer := 0;
  v_compartidas integer := 0;
  v_menos5     integer := 0;
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
      if v_f.n < 5 then v_menos5 := v_menos5 + 1; end if;
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
                                           'media', v_suma / nullif(v_nval, 0))
                        || case when v_menos5 > 0 then jsonb_build_object('menos_de_5', v_menos5) else '{}'::jsonb end end,
    'combinaciones_excluidas', v_excluidas);
end $$;

-- Informes de jefatura (decisión del 28/10/2026): como el del profesor/a, dos versiones.
--   completa: la de Dirección y administración (todo, con la marca «menos de 5»), «no entregar a la jefatura»;
--   jefatura: la que recibe la jefatura (mínimo de 5 y complementaria). Es la que se envía siempre.
-- Lo que cambia entre versiones lo decide el mismo ajuste que la versión docente (encuestas.version_docente).

create or replace function privado.informe_jefatura_departamento(p_curso text, p_persona integer)
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
  select id into v_curso from public.curso where nombre = p_curso;
  select * into v_pr from public.persona_responsable where id = p_persona;
  select array_agg(ca.ambito order by ca.ambito) into v_deps
  from public.cargo ca where ca.persona_id = p_persona and ca.curso_id = v_curso and ca.tipo = 'jefe_departamento';
  if v_pr.id is null or v_deps is null then
    raise exception 'Jefatura de departamento no encontrada' using errcode = 'P0002';
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

  return jsonb_build_object(
    'persona', jsonb_build_object('id', v_pr.id, 'nombre', v_pr.nombre, 'apellidos', v_pr.apellidos),
    'departamentos', to_jsonb(v_deps),
    'reuniones', v_sec,
    'alumnos', v_alu);
end $$;

revoke execute on function privado.informe_jefatura_departamento(text, integer) from public, anon, authenticated;

drop function if exists public.informe_jefe_departamento(text, integer, boolean);
create or replace function public.informe_jefe_departamento(p_curso text, p_persona integer, p_registrar boolean default false,
                                                             p_version text default 'completa')
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_previo text := current_setting('encuestas.version_docente', true);
  v_inf    jsonb;
begin
  perform permisos.exigir();
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a los informes de responsables' using errcode = '42501';
  end if;
  if p_version is null or p_version not in ('completa', 'jefatura') then
    raise exception 'Versión del informe no válida' using errcode = '22023';
  end if;
  if p_version = 'jefatura' then perform set_config('encuestas.version_docente', 'on', true); end if;
  v_inf := privado.informe_jefatura_departamento(p_curso, p_persona);
  perform set_config('encuestas.version_docente', coalesce(v_previo, ''), true);
  if p_registrar then
    perform privado.registrar('informe_responsable', jsonb_build_object('curso', p_curso, 'tipo', 'jefe_departamento',
      'ambito', array_to_string(array(select jsonb_array_elements_text(v_inf -> 'departamentos')), ', '), 'version', p_version));
  end if;
  return v_inf || jsonb_build_object('version', p_version);
end $$;

revoke execute on function public.informe_jefe_departamento(text, integer, boolean, text) from public, anon;
grant execute on function public.informe_jefe_departamento(text, integer, boolean, text) to authenticated;

-- Tramos del Equipo de Individuación que van juntos según el criterio vigente: cada tramo visible solo y los ocultos
-- juntos (§5.15). Con el criterio de Dirección, todos van solos.
create or replace function privado.grupos_equipo(p_curso text)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_r      jsonb := public.resultados(jsonb_build_object('curso', p_curso, 'colectivo', 'personal'),
                                      '{"tipo": "bloque", "codigo": "equipo_individualizacion"}', '{tramo}');
  v_vis    text[] := '{}';
  v_ocu    text[] := '{}';
  v_p      jsonb;
  v_grupos jsonb := '[]';
  v_t      text;
begin
  for v_p in select * from jsonb_array_elements(v_r -> 'partes') loop
    continue when v_p -> 'clave' ->> 'tramo' = '(sin dato)';
    if (v_p ->> 'suprimido')::boolean then v_ocu := v_ocu || (v_p -> 'clave' ->> 'tramo');
    else v_vis := v_vis || (v_p -> 'clave' ->> 'tramo'); end if;
  end loop;
  foreach v_t in array v_vis loop
    v_grupos := v_grupos || jsonb_build_object('tramos', jsonb_build_array(v_t));
  end loop;
  if cardinality(v_ocu) > 0 then
    v_grupos := v_grupos || jsonb_build_object('tramos', to_jsonb(v_ocu));
  end if;
  return v_grupos;
end $$;

revoke execute on function privado.grupos_equipo(text) from public, anon, authenticated;

-- Tramos con los que sale el informe de la jefatura de unos tramos: en la versión para la jefatura, los de su grupo.
create or replace function privado.tramos_jefatura(p_curso text, p_tramos text[])
returns text[]
language sql volatile security definer set search_path = '' as $$
  select coalesce(array_agg(distinct t order by t), p_tramos)
  from jsonb_array_elements(privado.grupos_equipo(p_curso)) g, jsonb_array_elements_text(g -> 'tramos') t
  where exists (select 1 from jsonb_array_elements_text(g -> 'tramos') x where x = any(p_tramos));
$$;

revoke execute on function privado.tramos_jefatura(text, text[]) from public, anon, authenticated;

drop function if exists public.listar_equipo(text);
create or replace function public.listar_equipo(p_curso text, p_version text default 'completa')
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_previo text := current_setting('encuestas.version_docente', true);
  v_grupos jsonb;
begin
  perform permisos.exigir();
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a los informes de responsables' using errcode = '42501';
  end if;
  if p_version = 'jefatura' then perform set_config('encuestas.version_docente', 'on', true); end if;
  v_grupos := privado.grupos_equipo(p_curso);
  perform set_config('encuestas.version_docente', coalesce(v_previo, ''), true);
  return coalesce((
    select jsonb_agg(g || jsonb_build_object('responsables', coalesce((
             select jsonb_agg(jsonb_build_object('nombre', pr.nombre, 'apellidos', pr.apellidos, 'tramo', ca.ambito)
                              order by array_position(array['infantil', 'y1_y5', 'y6_y9', 'y10_y12'], ca.ambito))
             from public.cargo ca
             join public.curso cu on cu.id = ca.curso_id
             join public.persona_responsable pr on pr.id = ca.persona_id
             where cu.nombre = p_curso and ca.tipo = 'jefe_equipo'
               and ca.ambito in (select jsonb_array_elements_text(g -> 'tramos'))), '[]'))
           order by array_position(array['infantil', 'y1_y5', 'y6_y9', 'y10_y12'], g -> 'tramos' ->> 0))
    from jsonb_array_elements(v_grupos) g
  ), '[]');
end $$;

revoke execute on function public.listar_equipo(text, text) from public, anon;
grant execute on function public.listar_equipo(text, text) to authenticated;

-- Informe del Equipo de Individuación de unos tramos. Con p_agrupar (versión para la jefatura) sale con los tramos de
-- su grupo (si su tramo queda oculto solo, junto con los demás ocultos), y devuelve los tramos con los que ha salido.
create or replace function privado.informe_jefatura_equipo(p_curso text, p_tramos text[], p_agrupar boolean)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_tramos text[] := case when p_agrupar then privado.tramos_jefatura(p_curso, p_tramos) else p_tramos end;
begin
  return jsonb_build_object('tramos', to_jsonb(v_tramos))
         || privado.informe_partes(p_curso, 'equipo_individualizacion', 'tramo', v_tramos);
end $$;

revoke execute on function privado.informe_jefatura_equipo(text, text[], boolean) from public, anon, authenticated;

drop function if exists public.informe_equipo(text, text[], boolean);
create or replace function public.informe_equipo(p_curso text, p_tramos text[], p_registrar boolean default false,
                                                  p_version text default 'completa')
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_previo text := current_setting('encuestas.version_docente', true);
  v_inf    jsonb;
begin
  perform permisos.exigir();
  if not permisos.ve_todo() then
    raise exception 'Sin acceso a los informes de responsables' using errcode = '42501';
  end if;
  if p_tramos is null or cardinality(p_tramos) = 0
     or not p_tramos <@ array['infantil', 'y1_y5', 'y6_y9', 'y10_y12'] then
    raise exception 'Tramos no válidos';
  end if;
  if p_version is null or p_version not in ('completa', 'jefatura') then
    raise exception 'Versión del informe no válida' using errcode = '22023';
  end if;
  if p_version = 'jefatura' then perform set_config('encuestas.version_docente', 'on', true); end if;
  v_inf := privado.informe_jefatura_equipo(p_curso, p_tramos, p_version = 'jefatura');
  perform set_config('encuestas.version_docente', coalesce(v_previo, ''), true);
  if p_registrar then
    perform privado.registrar('informe_responsable', jsonb_build_object('curso', p_curso, 'tipo', 'equipo_individuacion',
      'ambito', array_to_string(array(select jsonb_array_elements_text(v_inf -> 'tramos')), ', '), 'version', p_version));
  end if;
  return v_inf || jsonb_build_object('version', p_version);
end $$;

revoke execute on function public.informe_equipo(text, text[], boolean, text) from public, anon;
grant execute on function public.informe_equipo(text, text[], boolean, text) to authenticated;
