-- Revisión de lo que llega al navegador (06/11/2026): lo que la pantalla no enseña tampoco sale del servidor, para
-- ningún rol. Con el criterio de la coordinación, la versión docente y la de la jefatura:
--   1. resultados_profesor solo da el bloque del profesorado y sus preguntas (antes daba cualquier métrica, y con ella
--      la comparación del Colegio entero, de otras etapas).
--   2. La comparación con la etapa y el Colegio lleva solo la media (sin número de respuestas, valoraciones, NS/NC ni
--      distribución), y la del Colegio no sale si la métrica está en dos etapas: Colegio menos la etapa propia daría la
--      otra.
--   3. Quién nombró el alumnado: un docente nombrado por menos de 5 alumnos en una clase no aparece en las listas, ni
--      en el informe, ni cuenta entre los docentes de la clase (antes se sabía que 1 a 4 alumnos lo habían escrito).
--   4. La comparación por recomendación es solo de Dirección y administración (§7), también por resultados.
--   5. La referencia del Colegio en familias solo da las métricas que usa la pantalla.
--   6. Los aspectos con mayor y menor valoración no incluyen una pregunta oculta por complementaria.
--   7. Los correos del profesorado ya no se pueden leer directamente de la tabla (solo los usan las funciones de envío).

-- 3. Docentes nombrados por el alumnado: cuenta solo si llega al mínimo, por clase (o por asignatura en las optativas).
create or replace function privado.atribucion_visible(p_docente integer, p_curso smallint, p_etapa text,
                                                      p_cuest text default null, p_asig text default null, p_grupo text default null)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from privado.respuesta_docente rd
    join privado.respuesta r on r.id = rd.respuesta_id
    join public.cuestionario c on c.id = r.cuestionario_id
    join public.asignatura a on a.id = rd.asignatura_id
    left join public.grupo g on g.id = r.grupo_id
    where rd.docente_id = p_docente and c.curso_id = p_curso
      and (p_etapa is null or c.etapa = p_etapa)
      and (p_cuest is null or c.codigo = p_cuest)
      and (p_asig is null or a.nombre = p_asig)
      and (p_grupo is null or g.nombre = p_grupo)
    group by c.id, rd.asignatura_id,
             case when exists (select 1 from public.asignacion_docente ad join public.grupo g2 on g2.id = ad.grupo_id
                               where ad.curso_id = p_curso and ad.asignatura_id = rd.asignatura_id and g2.etapa = c.etapa)
                  then r.grupo_id end
    having count(distinct r.id) >= privado.minimo());
$$;
revoke execute on function privado.atribucion_visible(integer, smallint, text, text, text, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION privado.etapa_para_docente(p_perfil usuario_perfil, p_curso smallint, p_docente integer)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  ) and not privado.atribucion_visible(p_docente, p_curso, p_perfil.etapa) then
    raise exception 'Sin acceso a este profesor/a' using errcode = '42501';
  end if;
  return p_perfil.etapa;
end $function$;

CREATE OR REPLACE FUNCTION public.listar_profesores(p_curso text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_perfil public.usuario_perfil := permisos.exigir();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', pr.id, 'nombre', pr.nombre, 'apellidos', pr.apellidos,
             'departamento', dep.nombre, 'situacion', pr.situacion)
           order by pr.apellidos, pr.nombre)
    from public.persona_responsable pr
    left join public.departamento dep on dep.id = pr.departamento_id
    where exists (
        select 1 from public.asignacion_docente ad
        join public.curso cu on cu.id = ad.curso_id
        join public.grupo g on g.id = ad.grupo_id
        where ad.docente_id = pr.id and cu.nombre = p_curso
          and (v_perfil.rol <> 'coordinacion' or g.etapa = v_perfil.etapa))
      or privado.atribucion_visible(pr.id, (select id from public.curso where nombre = p_curso),
                                    case when v_perfil.rol = 'coordinacion' then v_perfil.etapa end)
  ), '[]');
end $function$;

CREATE OR REPLACE FUNCTION public.profesores_de_clase(p_curso text, p_filtro jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_perfil public.usuario_perfil := permisos.exigir();
  v_cuest  text := p_filtro ->> 'cuestionario';
  v_asig   text := p_filtro ->> 'asignatura';
  v_grupo  text := p_filtro ->> 'grupo';
begin
  if v_cuest is null or v_asig is null then
    raise exception 'Faltan el cuestionario y la asignatura' using errcode = '22023';
  end if;
  return coalesce((
    select jsonb_agg(distinct pr.id order by pr.id)
    from public.persona_responsable pr
    where exists (
        -- Asignación: da la asignatura en un grupo con respuestas de ese cuestionario.
        select 1 from public.asignacion_docente ad
        join public.curso cu on cu.id = ad.curso_id
        join public.grupo g on g.id = ad.grupo_id
        join public.asignatura a on a.id = ad.asignatura_id
        where ad.docente_id = pr.id and cu.nombre = p_curso and a.nombre = v_asig
          and (v_grupo is null or g.nombre = v_grupo)
          and (v_perfil.rol <> 'coordinacion' or g.etapa = v_perfil.etapa)
          and exists (select 1 from privado.respuesta r join public.cuestionario c on c.id = r.cuestionario_id
                      where r.grupo_id = g.id and c.codigo = v_cuest and c.curso_id = cu.id))
      -- Atribución: el alumnado de ese cuestionario escribió su nombre para esa asignatura (al menos el mínimo).
      or privado.atribucion_visible(pr.id, (select id from public.curso where nombre = p_curso),
                                    case when v_perfil.rol = 'coordinacion' then v_perfil.etapa end, v_cuest, v_asig, v_grupo)
  ), '[]');
end $function$;

-- 3. En el informe: los mismos docentes.
CREATE OR REPLACE FUNCTION privado.clases(p_curso smallint, p_docentes integer[], p_metrica jsonb, p_etapa text DEFAULT NULL::text)
 RETURNS TABLE(docente_id integer, cuestionario text, etapa text, grupo text, asignatura text, tipo text, docentes_clase integer, motivo text, n integer, datos jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_c        record;
  v_minimo   integer := privado.minimo();
  v_vis      integer[];
  v_a        record;
  a_k1 text[]; a_k2 text[]; a_g1 boolean[]; a_g2 boolean[]; a_n integer[]; a_d jsonb[];
  v_mot      text[];
  b_k1 text[]; b_g1 boolean[]; b_n integer[]; b_d jsonb[];
  b_mot      text[];
  v_gid      integer;
  v_aid      integer;
  v_doc      integer[];
  v_atr      integer[];
  v_todos    integer[];
  v_mot_t    text;
  v_d        integer;
  i integer; j integer;
begin
  for v_c in
    select c.id, c.codigo, c.etapa from public.cuestionario c
    where c.curso_id = p_curso and c.colectivo = 'alumnos' and (p_etapa is null or c.etapa = p_etapa)
      and (exists (select 1 from public.asignacion_docente ad join public.grupo g on g.id = ad.grupo_id
                   where ad.curso_id = p_curso and ad.docente_id = any(p_docentes) and g.etapa = c.etapa
                     and exists (select 1 from privado.respuesta r where r.cuestionario_id = c.id and r.grupo_id = g.id))
           or exists (select 1 from privado.respuesta_docente rd join privado.respuesta r on r.id = rd.respuesta_id
                      where r.cuestionario_id = c.id and rd.docente_id = any(p_docentes)))
    order by c.id
  loop
    select array_agg(x.k1), array_agg(x.k2), array_agg(x.agg1), array_agg(x.agg2), array_agg(x.n), array_agg(x.datos), array_agg(x.motivo)
      into a_k1, a_k2, a_g1, a_g2, a_n, a_d, v_mot
    from privado.celdas_suprimidas(array[v_c.id], array['grupo', 'asignatura'], p_metrica) x;

    for i in 1 .. coalesce(cardinality(a_n), 0) loop
      continue when a_g1[i] or a_g2[i];
      select g.id into v_gid from public.grupo g where g.curso_id = p_curso and g.nombre = a_k1[i];
      select a.id into v_aid from public.asignatura a where a.curso_id = p_curso and a.nombre = a_k2[i];
      select array_agg(ad.docente_id order by ad.docente_id) into v_doc
      from public.asignacion_docente ad
      where ad.curso_id = p_curso and ad.grupo_id = v_gid and ad.asignatura_id = v_aid;
      -- Docentes atribuidos por nombre en esta clase (pueden no ser los titulares de Alexia).
      select array_agg(distinct rd.docente_id) into v_atr
      from privado.respuesta_docente rd join privado.respuesta r on r.id = rd.respuesta_id
      where r.cuestionario_id = v_c.id and r.grupo_id = v_gid and rd.asignatura_id = v_aid;
      -- Sin titular en Alexia para esta clase (las optativas): va por cuestionario, más abajo.
      continue when v_doc is null;
      v_todos := array(select distinct x from unnest(coalesce(v_doc, '{}') || coalesce(v_atr, '{}')) x order by x);
      continue when cardinality(v_todos) = 0 or not (v_todos && p_docentes);

      if v_atr is null and cardinality(v_doc) = 1 then
        return query select v_doc[1], v_c.codigo, v_c.etapa, a_k1[i], a_k2[i], 'propia'::text, 1, v_mot[i], a_n[i], a_d[i];
        continue;
      end if;

      if v_atr is null then
        return query select x, v_c.codigo, v_c.etapa, a_k1[i], a_k2[i], 'compartida'::text, cardinality(v_doc), v_mot[i], a_n[i], a_d[i]
                     from unnest(v_doc) x where x = any(p_docentes);
        continue;
      end if;

      select array_agg(y.k1), array_agg(y.agg1), array_agg(y.n), array_agg(y.datos), array_agg(y.motivo)
        into b_k1, b_g1, b_n, b_d, b_mot
      from privado.celdas_suprimidas(array[v_c.id], array['docente_atribuido'],
             p_metrica || jsonb_build_object('grupo_id', v_gid, 'asignatura_id', v_aid)) y;
      continue when b_n is null;
      -- Cada docente nombrado recibe su subconjunto. Un titular al que no nombró nadie (por
      -- ejemplo, de baja) no recibe nada de esta clase.
      -- Docentes de la clase que se pueden nombrar: los titulares y los nombrados por al menos el mínimo de alumnos.
      v_vis := array(select x from unnest(v_todos) x
                     where x = any(v_doc) or (select count(distinct r.id) from privado.respuesta_docente rd
                                              join privado.respuesta r on r.id = rd.respuesta_id
                                              where r.cuestionario_id = v_c.id and r.grupo_id = v_gid and rd.asignatura_id = v_aid
                                                and rd.docente_id = x) >= v_minimo);
      foreach v_d in array v_vis loop
        continue when not v_d = any(p_docentes);
        j := null;
        for k in 1 .. cardinality(b_n) loop
          if not b_g1[k] and b_k1[k] = v_d::text then j := k; end if;
        end loop;
        continue when j is null;
        return query select v_d, v_c.codigo, v_c.etapa, a_k1[i], a_k2[i], 'atribuida'::text, cardinality(v_vis),
                            case when v_mot[i] is not null then coalesce(b_mot[j], 'complementaria') else b_mot[j] end, b_n[j], b_d[j];
      end loop;
    end loop;

    -- Asignaturas atribuidas sin asignación por grupo (optativas): por cuestionario.
    for v_a in
      select distinct rd.asignatura_id, a.nombre
      from privado.respuesta_docente rd
      join privado.respuesta r on r.id = rd.respuesta_id
      join public.asignatura a on a.id = rd.asignatura_id
      where r.cuestionario_id = v_c.id and rd.docente_id = any(p_docentes)
        and not exists (select 1 from public.asignacion_docente ad join public.grupo g on g.id = ad.grupo_id
                        where ad.curso_id = p_curso and ad.asignatura_id = rd.asignatura_id and g.etapa = v_c.etapa)
    loop
      -- Estado de la asignatura entera en la tabla del cuestionario (margen de la columna).
      v_mot_t := null;
      for i in 1 .. coalesce(cardinality(a_n), 0) loop
        if a_g1[i] and not a_g2[i] and a_k2[i] = v_a.nombre then v_mot_t := v_mot[i]; end if;
      end loop;
      select array_agg(y.k1), array_agg(y.agg1), array_agg(y.n), array_agg(y.datos), array_agg(y.motivo)
        into b_k1, b_g1, b_n, b_d, b_mot
      from privado.celdas_suprimidas(array[v_c.id], array['docente_atribuido'],
             p_metrica || jsonb_build_object('asignatura_id', v_a.asignatura_id)) y;
      continue when b_n is null;
      for j in 1 .. cardinality(b_n) loop
        continue when b_g1[j];
        continue when b_k1[j] = '(sin dato)';
        continue when not b_k1[j]::integer = any(p_docentes);
        continue when (select count(distinct rd2.respuesta_id) from privado.respuesta_docente rd2
                         join privado.respuesta r2 on r2.id = rd2.respuesta_id
                        where r2.cuestionario_id = v_c.id and rd2.asignatura_id = v_a.asignatura_id
                          and rd2.docente_id = b_k1[j]::integer) < v_minimo;
        return query select b_k1[j]::integer, v_c.codigo, v_c.etapa, null::text, v_a.nombre, 'atribuida'::text,
                            (select count(*)::integer from (
                               select rd2.docente_id from privado.respuesta_docente rd2
                               join privado.respuesta r2 on r2.id = rd2.respuesta_id
                              where r2.cuestionario_id = v_c.id and rd2.asignatura_id = v_a.asignatura_id
                              group by rd2.docente_id having count(distinct r2.id) >= v_minimo) z),
                            case when v_mot_t is not null then coalesce(b_mot[j], 'complementaria') else b_mot[j] end,
                            b_n[j], b_d[j];
      end loop;
    end loop;
  end loop;
end $function$;

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

-- 1. resultados_profesor: solo el bloque del profesorado y sus preguntas (lo que usa la pantalla).
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
  if not (p_metrica = '{"tipo": "bloque", "codigo": "profesorado"}'::jsonb
          or (p_metrica ->> 'tipo' = 'pregunta' and exists (
                select 1 from public.pregunta_cuestionario pc join public.pregunta p on p.id = pc.pregunta_id
                join public.bloque b on b.id = pc.bloque_id join public.cuestionario c on c.id = pc.cuestionario_id
                where c.curso_id = v_curso and b.codigo = 'profesorado' and p.codigo_diccionario = p_metrica ->> 'codigo'))) then
    raise exception 'Solo el bloque del profesorado y sus preguntas' using errcode = '22023';
  end if;
  v_etapa := privado.etapa_para_docente(v_perfil, v_curso, p_docente);
  if not privado.ve_menos_de_5() and p_metrica ->> 'tipo' = 'pregunta' then
    select x -> 'resultado' into v_r
    from jsonb_array_elements(privado.informe_profesor(v_curso, p_docente, v_etapa) -> 'preguntas') x
    where x ->> 'codigo' = p_metrica ->> 'codigo';
    if v_r is not null then return v_r; end if;
  end if;
  return privado.resultados_profesor(v_curso, p_docente, p_metrica, v_etapa);
end $$;

CREATE OR REPLACE FUNCTION privado.resolver(p_filtro jsonb, p_dims text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_perfil     public.usuario_perfil := privado.exigir_o_enlace();
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
    when 'alumnos'  then array['cuestionario', 'etapa', 'grupo', 'asignatura', 'recomienda']
    when 'familias' then array['etapa', 'recomienda']
    else array['docente', 'antiguedad', 'departamento_equipo', 'departamento', 'tramo', 'recomienda']
  end;

  for k in select jsonb_object_keys(v_filtro) loop
    if k not in ('curso', 'colectivo', 'referencia') and not k = any(v_particion)
       and not (v_col = 'alumnos' and k = 'etapas') then
      raise exception 'Filtro no válido para %: %', v_col, k;
    end if;
  end loop;
  foreach k in array coalesce(p_dims, '{}') loop
    if not k = any(v_particion) then
      raise exception 'Dimensión no válida para %: %', v_col, k;
    end if;
  end loop;

  -- Referencia del colegio (decisión del 26/10/2026): la coordinación puede ver el resultado de las familias de
  -- todo el colegio, sin repartir ni filtrar, junto al de su etapa. Es un agregado del colegio entero.
  if v_filtro ? 'referencia' then
    if v_col <> 'familias' or (v_filtro ->> 'referencia') <> 'true' or cardinality(coalesce(p_dims, '{}')) > 0
       or exists (select 1 from jsonb_object_keys(v_filtro) x where x not in ('curso', 'colectivo', 'referencia')) then
      raise exception 'La referencia del Colegio es solo el total de familias, sin filtros ni repartos';
    end if;
    v_filtro := v_filtro - 'referencia';
  elsif v_perfil.rol = 'coordinacion' then
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
    and (v_col <> 'alumnos' or not v_filtro ? 'cuestionario' or c.codigo = v_filtro ->> 'cuestionario')
    and (v_col <> 'alumnos' or not v_filtro ? 'etapas'
         or c.etapa = any(array(select jsonb_array_elements_text(v_filtro -> 'etapas'))));
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

  -- La comparación por recomendación va sola: sin grupo, etapa, segmento ni ningún otro filtro.
  -- 4. La comparación por recomendación es solo de Dirección y administración (§7).
  if ('recomienda' = any(v_dims) or v_fijos ? 'recomienda') and coalesce(v_perfil.rol::text, '') not in ('direccion', 'administrador') then
    raise exception 'La comparación por recomendación es solo de Dirección y administración' using errcode = '42501';
  end if;
  if 'recomienda' = any(v_dims) and cardinality(v_dims) > 1 then
    raise exception 'La comparación por recomendación no se combina con otros filtros';
  end if;

  if cardinality(v_dims) > 2 then
    raise exception 'Como máximo dos dimensiones a la vez';
  end if;

  if v_col = 'personal' then
    select count(*) into v_seg from unnest(v_dims) d
    where d in ('docente', 'antiguedad', 'departamento_equipo', 'tramo');
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
end $function$;

-- Resultados públicos: igual que antes, con la supresión conjunta.
create or replace function public.resultados(p_filtro jsonb, p_metrica jsonb, p_dimensiones text[] default '{}')
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_res     jsonb;
  v_dims    text[];
  v_fijos   jsonb;
  v_cuest   integer[];
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
  perform privado.exigir_metrica_publica(p_metrica);
  -- 5. La referencia del Colegio en familias: solo lo que enseña la pantalla.
  if p_filtro ? 'referencia' and p_metrica ->> 'tipo' not in ('personas', 'satisfaccion', 'recomendacion', 'bloque') then
    raise exception 'La referencia del Colegio no da esta métrica' using errcode = '22023';
  end if;
  v_res := privado.resolver(p_filtro, p_dimensiones);
  v_dims := array(select jsonb_array_elements_text(v_res -> 'dims'));
  v_fijos := v_res -> 'fijos';
  v_cuest := array(select jsonb_array_elements_text(v_res -> 'cuestionarios')::integer);

  select array_agg(c.k1), array_agg(c.k2), array_agg(c.agg1), array_agg(c.agg2), array_agg(c.n), array_agg(c.datos), array_agg(c.motivo)
    into a_k1, a_k2, a_g1, a_g2, a_n, a_d, v_mot
  from privado.celdas_suprimidas(v_cuest, v_dims, p_metrica) c;

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

CREATE OR REPLACE FUNCTION public.puntos_colectivo(p_filtro jsonb, p_cuantos integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  -- 6. Fuera del criterio de Dirección, sin las preguntas ocultas por complementaria (se miran solo las que podrían
  -- entrar en las listas, de las dos puntas).
  if not privado.ve_menos_de_5() then
    select coalesce(jsonb_agg(e), '[]') into v_filas
    from jsonb_array_elements(v_filas) e
    where (e in (select e2 from jsonb_array_elements(v_filas) e2 order by (e2 ->> 'media')::numeric limit p_cuantos * 3)
           or e in (select e2 from jsonb_array_elements(v_filas) e2 order by (e2 ->> 'media')::numeric desc limit p_cuantos * 3))
      and not (public.resultados(p_filtro, jsonb_build_object('tipo', 'pregunta', 'codigo', e ->> 'codigo')) -> 'total' ->> 'suprimido')::boolean;
  end if;
  return jsonb_build_object(
    'mejora', coalesce((select jsonb_agg(e order by (e ->> 'media')::numeric, (e ->> 'pct_bajo')::numeric desc)
                        from (select e from jsonb_array_elements(v_filas) e order by (e ->> 'media')::numeric, (e ->> 'pct_bajo')::numeric desc limit p_cuantos) z), '[]'),
    'fuertes', coalesce((select jsonb_agg(e order by (e ->> 'media')::numeric desc, (e ->> 'pct_bajo')::numeric)
                        from (select e from jsonb_array_elements(v_filas) e order by (e ->> 'media')::numeric desc, (e ->> 'pct_bajo')::numeric limit p_cuantos) z), '[]'));
end $function$;

-- 7. Correos del profesorado: fuera de la lectura directa (las funciones de envío los leen como propietario).
revoke select on public.persona_responsable from authenticated;
grant select (id, nombre, apellidos, departamento_id, situacion) on public.persona_responsable to authenticated;
