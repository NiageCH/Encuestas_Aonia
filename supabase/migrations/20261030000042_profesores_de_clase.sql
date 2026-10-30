-- Navegar al detalle (30/10/2026): al pulsar una asignatura en Alumnado, la lista del profesorado se limita a quienes dan
-- esa asignatura en ese cuestionario (y en ese grupo, si está elegido). Devuelve solo identificadores de docentes, que el
-- cliente cruza con listar_profesores: ningún resultado. Mismo criterio que listar_profesores (asignación de Alexia o
-- atribución por nombre) y la misma restricción para la coordinación: solo su etapa.
--
-- Numeración: 42, después de las migraciones locales de la Fase 2 (33 a 41), que no están en la nube.

create function public.profesores_de_clase(p_curso text, p_filtro jsonb)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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
      or exists (
        -- Atribución: el alumnado de ese cuestionario escribió su nombre para esa asignatura.
        select 1 from privado.respuesta_docente rd
        join privado.respuesta r on r.id = rd.respuesta_id
        join public.cuestionario c on c.id = r.cuestionario_id
        join public.curso cu on cu.id = c.curso_id
        join public.asignatura a on a.id = rd.asignatura_id
        left join public.grupo g on g.id = r.grupo_id
        where rd.docente_id = pr.id and cu.nombre = p_curso and c.codigo = v_cuest and a.nombre = v_asig
          and (v_grupo is null or g.nombre = v_grupo)
          and (v_perfil.rol <> 'coordinacion' or c.etapa = v_perfil.etapa))
  ), '[]');
end $$;

revoke execute on function public.profesores_de_clase(text, jsonb) from public, anon;
grant execute on function public.profesores_de_clase(text, jsonb) to authenticated;
