-- Decisión del 13/10/2026: la coordinación de etapa ve también la media del colegio en la
-- vista de profesor, como referencia. Sigue sin ver profesores ni grupos de otras etapas.

create or replace function public.resultados_profesor(
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

  -- Comparación con la media de cada etapa en la que tiene resultados visibles y con la
  -- del colegio. La coordinación también recibe la del colegio, como referencia: es un
  -- agregado de todo el colegio, no resultados de profesores ni grupos de otras etapas.
  foreach v_e in array v_etapas loop
    select privado.fila(jsonb_build_object('etapa', v_e), case when x.n < 5 then 'menos_de_5' end, x.n, x.datos)
      into v_cmp
    from privado.celdas(
      array(select c.id from public.cuestionario c where c.curso_id = v_curso and c.colectivo = 'alumnos' and c.etapa = v_e),
      '{}', p_metrica) x;
    v_comp := v_comp || jsonb_build_object(v_e, v_cmp);
  end loop;
  begin
    select privado.fila('{}', case when x.n < 5 then 'menos_de_5' end, x.n, x.datos)
      into v_cmp
    from privado.celdas(
      array(select c.id from public.cuestionario c where c.curso_id = v_curso and c.colectivo = 'alumnos'),
      '{}', p_metrica) x;
    v_comp := v_comp || jsonb_build_object('colegio', v_cmp);
  end;

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
