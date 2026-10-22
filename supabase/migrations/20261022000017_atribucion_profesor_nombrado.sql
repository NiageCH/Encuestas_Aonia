-- Respuesta del colegio del 22/10/2026: por las bajas, los alumnos nombran al profesor que más
-- tiempo les ha dado clase, que no siempre es el titular de Alexia. La valoración va al informe del
-- profesor nombrado:
--   * en una clase con atribución, los docentes son los titulares más los nombrados;
--   * cada uno recibe su subconjunto (con la complementaria entre ellos y los alumnos sin atribuir);
--   * un titular al que no nombró nadie no recibe nada de esa clase.
-- Una clase con un solo titular y sin atribución sigue siendo propia.

create or replace function privado.clases(p_curso smallint, p_docentes integer[], p_metrica jsonb, p_etapa text default null)
returns table (docente_id integer, cuestionario text, etapa text, grupo text, asignatura text,
               tipo text, docentes_clase integer, motivo text, n integer, datos jsonb)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_c        record;
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
    select array_agg(x.k1), array_agg(x.k2), array_agg(x.agg1), array_agg(x.agg2), array_agg(x.n), array_agg(x.datos)
      into a_k1, a_k2, a_g1, a_g2, a_n, a_d
    from privado.celdas(array[v_c.id], array['grupo', 'asignatura'], p_metrica) x;
    v_mot := privado.suprimir(a_k1, a_k2, a_g1, a_g2, a_n);

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

      select array_agg(y.k1), array_agg(y.agg1), array_agg(y.n), array_agg(y.datos)
        into b_k1, b_g1, b_n, b_d
      from privado.celdas(array[v_c.id], array['docente_atribuido'],
             p_metrica || jsonb_build_object('grupo_id', v_gid, 'asignatura_id', v_aid)) y;
      b_mot := privado.suprimir(b_k1, array_fill(null::text, array[cardinality(b_n)]), b_g1,
                                array_fill(true, array[cardinality(b_n)]), b_n);
      -- Cada docente nombrado recibe su subconjunto. Un titular al que no nombró nadie (por
      -- ejemplo, de baja) no recibe nada de esta clase.
      foreach v_d in array v_todos loop
        continue when not v_d = any(p_docentes);
        j := null;
        for k in 1 .. cardinality(b_n) loop
          if not b_g1[k] and b_k1[k] = v_d::text then j := k; end if;
        end loop;
        continue when j is null;
        return query select v_d, v_c.codigo, v_c.etapa, a_k1[i], a_k2[i], 'atribuida'::text, cardinality(v_todos),
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
      select array_agg(y.k1), array_agg(y.agg1), array_agg(y.n), array_agg(y.datos)
        into b_k1, b_g1, b_n, b_d
      from privado.celdas(array[v_c.id], array['docente_atribuido'],
             p_metrica || jsonb_build_object('asignatura_id', v_a.asignatura_id)) y;
      b_mot := privado.suprimir(b_k1, array_fill(null::text, array[cardinality(b_n)]), b_g1,
                                array_fill(true, array[cardinality(b_n)]), b_n);
      for j in 1 .. cardinality(b_n) loop
        continue when b_g1[j];
        continue when b_k1[j] = '(sin dato)';
        continue when not b_k1[j]::integer = any(p_docentes);
        return query select b_k1[j]::integer, v_c.codigo, v_c.etapa, null::text, v_a.nombre, 'atribuida'::text,
                            (select count(distinct rd2.docente_id)::integer from privado.respuesta_docente rd2
                               join privado.respuesta r2 on r2.id = rd2.respuesta_id
                              where r2.cuestionario_id = v_c.id and rd2.asignatura_id = v_a.asignatura_id),
                            case when v_mot_t is not null then coalesce(b_mot[j], 'complementaria') else b_mot[j] end,
                            b_n[j], b_d[j];
      end loop;
    end loop;
  end loop;
end $$;

revoke execute on function privado.clases(smallint, integer[], jsonb, text) from public;
