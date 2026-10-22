-- Respuestas del colegio del 21/10/2026: departamentos oficiales y jefes, Equipo de
-- Individuación por tramo de tutoría (aislado de todo lo demás), clases propias, compartidas
-- y atribuidas por nombre en el informe del profesor.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(53);

-- Datos añadidos para este fichero (inventados) ----------------------------------------------
do $$
declare
  v_curso smallint := (select id from public.curso where nombre = '2000/01');
  v_per integer := (select id from public.cuestionario where curso_id = v_curso and codigo = 'PER_T');
  v_bach integer; b_ei integer; b_prof integer; q_ei integer;
  q_clar integer := (select id from public.pregunta where codigo_diccionario = 'prof_claridad');
  q_trato integer := (select id from public.pregunta where codigo_diccionario = 'prof_trato');
  v_fis integer; v_qui integer; v_cien integer;
  v_tres integer; v_cuatro integer; v_cinco integer; v_seis integer; v_siete integer;
  v_dos integer := (select id from public.persona_responsable where correo = 'docente.dos@ejemplo.test');
  a_qui integer; a_opt integer; a_len integer := (select id from public.asignatura where curso_id = v_curso and nombre = 'Lengua');
  g_a integer; g_b integer; r bigint; x record; n integer := 0; s integer;
begin
  -- Equipo de Individuación: 18 tutores; Y6 a Y9 7, Y10 a Y12 5, Y1 a Y5 4, Infantil 2.
  insert into public.pregunta (codigo_diccionario, texto_es, tipo, escala_min, escala_max)
    values ('ei_utiles', 'Las reuniones del equipo son útiles', 'escala', 1, 6) returning id into q_ei;
  insert into public.bloque (cuestionario_id, codigo, nombre, orden, entra_en_media)
    values (v_per, 'equipo_individualizacion', 'Equipo de Individuación', 5, false) returning id into b_ei;
  insert into public.pregunta_cuestionario (cuestionario_id, pregunta_id, bloque_id, orden) values (v_per, q_ei, b_ei, 1);
  for x in select id from privado.respuesta where cuestionario_id = v_per order by id limit 18 loop
    n := n + 1;
    insert into privado.respuesta_item (respuesta_id, pregunta_id, valor, ns_nc) values (x.id, q_ei, 1 + n % 6, false);
    insert into privado.respuesta_tramo values (x.id,
      case when n <= 7 then 'y6_y9' when n <= 12 then 'y10_y12' when n <= 16 then 'y1_y5' else 'infantil' end);
  end loop;

  -- Departamentos oficiales: la unidad «Ciencias» de la encuesta cubre Física y Química.
  v_cien := (select id from public.departamento where curso_id = v_curso and nombre = 'Ciencias');
  insert into public.departamento (curso_id, nombre) values (v_curso, 'Física') returning id into v_fis;
  insert into public.departamento (curso_id, nombre) values (v_curso, 'Química') returning id into v_qui;
  insert into public.departamento_equivalencia values (v_cien, v_fis), (v_cien, v_qui);

  insert into public.persona_responsable (nombre, apellidos, correo) values ('Docente', 'Tres', 'docente.tres@ejemplo.test') returning id into v_tres;
  insert into public.persona_responsable (nombre, apellidos, correo) values ('Docente', 'Cuatro', 'docente.cuatro@ejemplo.test') returning id into v_cuatro;
  insert into public.persona_responsable (nombre, apellidos, correo) values ('Docente', 'Cinco', 'docente.cinco@ejemplo.test') returning id into v_cinco;
  insert into public.persona_responsable (nombre, apellidos, correo) values ('Docente', 'Seis', 'docente.seis@ejemplo.test') returning id into v_seis;
  insert into public.persona_responsable (nombre, apellidos, correo) values ('Docente', 'Siete', 'docente.siete@ejemplo.test') returning id into v_siete;

  insert into public.cargo (persona_id, curso_id, tipo, ambito) values
    (v_dos, v_curso, 'jefe_departamento', 'Letras'), (v_dos, v_curso, 'jefe_departamento', 'Artes'),
    (v_tres, v_curso, 'jefe_departamento', 'Física'), (v_tres, v_curso, 'jefe_departamento', 'Química'),
    (v_cuatro, v_curso, 'jefe_departamento', 'Ciencias'), (v_cuatro, v_curso, 'jefe_departamento', 'Artes');

  -- Clase compartida sin atribución: Lengua de Y7 D con dos docentes.
  insert into public.asignacion_docente (curso_id, grupo_id, asignatura_id, docente_id)
    select v_curso, g.id, a_len, d from public.grupo g, unnest(array[v_tres, v_cuatro]) d
    where g.curso_id = v_curso and g.nombre = 'Y7 D';

  -- Profesor nombrado que no es el titular (bajas): en Lengua de Y7 B el titular es Dos, pero
  -- los 8 alumnos nombran a Cuatro.
  insert into privado.respuesta_docente (respuesta_id, asignatura_id, docente_id)
    select r.id, a_len, v_cuatro from privado.respuesta r join public.grupo g on g.id = r.grupo_id
    where g.curso_id = v_curso and g.nombre = 'Y7 B';

  -- Bachillerato con atribución por nombre:
  --   Química Y11 A, 14 alumnos: Cinco 8, Seis 6 (los dos visibles).
  --   Química Y11 B, 10 alumnos: Cinco 6, Seis 4 (Seis oculto y Cinco por complementaria).
  --   Optativa (sin asignación por grupo): Siete 7 alumnos entre los dos grupos, 17 sin atribuir.
  insert into public.cuestionario (curso_id, colectivo, etapa, codigo, titulo)
    values (v_curso, 'alumnos', 'bachillerato', 'BACH_T', 'Bachillerato de prueba') returning id into v_bach;
  insert into public.bloque (cuestionario_id, codigo, nombre, orden) values (v_bach, 'profesorado', 'Profesorado', 1) returning id into b_prof;
  insert into public.pregunta_cuestionario (cuestionario_id, pregunta_id, bloque_id, orden, por_asignatura) values
    (v_bach, q_clar, b_prof, 1, true), (v_bach, q_trato, b_prof, 2, true);
  insert into public.asignatura (curso_id, nombre) values (v_curso, 'Química') returning id into a_qui;
  insert into public.asignatura (curso_id, nombre) values (v_curso, 'Optativa') returning id into a_opt;
  insert into public.grupo (curso_id, etapa, nivel, nombre) values (v_curso, 'bachillerato', 'Y11', 'Y11 A') returning id into g_a;
  insert into public.grupo (curso_id, etapa, nivel, nombre) values (v_curso, 'bachillerato', 'Y11', 'Y11 B') returning id into g_b;
  insert into public.asignacion_docente (curso_id, grupo_id, asignatura_id, docente_id) values
    (v_curso, g_a, a_qui, v_cinco), (v_curso, g_a, a_qui, v_seis), (v_curso, g_b, a_qui, v_cinco), (v_curso, g_b, a_qui, v_seis);
  for x in select * from (values (g_a, 14, 8), (g_b, 10, 6)) t(g, tam, cinco) loop
    for s in 1 .. x.tam loop
      insert into privado.respuesta (cuestionario_id, grupo_id) values (v_bach, x.g) returning id into r;
      insert into privado.respuesta_item (respuesta_id, pregunta_id, asignatura_id, valor, ns_nc) values
        (r, q_clar, a_qui, 1 + (s % 6), false), (r, q_trato, a_qui, 1 + ((s + 2) % 6), false),
        (r, q_clar, a_opt, 1 + ((s + 1) % 6), false), (r, q_trato, a_opt, 6 - (s % 6), false);
      insert into privado.respuesta_docente values (r, a_qui, case when s <= x.cinco then v_cinco else v_seis end);
      if (x.g = g_a and s <= 4) or (x.g = g_b and s <= 3) then
        insert into privado.respuesta_docente values (r, a_opt, v_siete);
      end if;
    end loop;
  end loop;
end $$;

create temp table ids as
  select (select id from public.persona_responsable where apellidos = 'Dos') as dos,
         (select id from public.persona_responsable where apellidos = 'Tres') as tres,
         (select id from public.persona_responsable where apellidos = 'Cuatro') as cuatro,
         (select id from public.persona_responsable where apellidos = 'Cinco') as cinco,
         (select id from public.persona_responsable where apellidos = 'Siete') as siete,
         (select avg(i.valor) from privado.respuesta_item i
            join privado.respuesta_docente rd on rd.respuesta_id = i.respuesta_id and rd.asignatura_id = i.asignatura_id
            join privado.respuesta r on r.id = i.respuesta_id join public.grupo g on g.id = r.grupo_id
            where g.nombre = 'Y11 A' and rd.docente_id = (select id from public.persona_responsable where apellidos = 'Cinco')
              and i.valor is not null) as cinco_y11a;
grant select on ids to authenticated;

create function pg_temp.celda(p jsonb, p_grupo text, p_asig text) returns jsonb language sql as $$
  select c from jsonb_array_elements(p -> 'celdas') c
  where c -> 'clave' ->> 'asignatura' = p_asig and (c -> 'clave' ->> 'grupo') is not distinct from p_grupo limit 1 $$;
grant execute on function pg_temp.celda(jsonb, text, text) to authenticated;

-- Tramo de tutoría ----------------------------------------------------------------------------
set local role postgres; select pg_temp.como('direccion'); set local role authenticated;

select is(public.listar_equipo('2000/01') -> 0 -> 'tramos', '["infantil", "y1_y5"]'::jsonb,
  'los tramos ocultos (Infantil 2 e Y1 a Y5 4) se juntan en un resultado compartido');
select is(jsonb_array_length(public.listar_equipo('2000/01')), 3, 'tres resultados: compartido, Y6 a Y9 e Y10 a Y12');
select is((public.informe_equipo('2000/01', '{y6_y9}') -> 'total' ->> 'n')::int, 7, 'Y6 a Y9: 7 tutores, visible');
select is((public.informe_equipo('2000/01', '{y10_y12}') -> 'total' ->> 'n')::int, 5, 'Y10 a Y12: 5 tutores, visible');
select is(public.informe_equipo('2000/01', '{y1_y5}') -> 'total' ->> 'motivo', 'menos_de_5', 'Y1 a Y5 solo: oculto');
select is((public.informe_equipo('2000/01', '{infantil,y1_y5}') -> 'total' ->> 'n')::int, 6, 'Infantil y Y1 a Y5 juntos: 6, visible');
select is(public.informe_equipo('2000/01', '{y6_y9,infantil}') -> 'total' ->> 'motivo', 'complementaria',
  'un conjunto con una parte visible y otra oculta se oculta (la resta destaparía la oculta)');
select is(jsonb_array_length(public.informe_equipo('2000/01', '{infantil,y1_y5}') -> 'preguntas'), 1, 'el conjunto trae también el detalle por pregunta');

-- El tramo no es accesible desde ninguna otra RPC ni métrica
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal"}', '{"tipo":"personas"}', '{tramo}') $$,
  'P0001', 'El tramo de tutoría solo vale para el bloque del Equipo de Individuación', 'no se cuentan personas por tramo');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal","tramo":"y6_y9"}', '{"tipo":"bloque","codigo":"superiores"}') $$,
  'P0001', 'El tramo de tutoría solo vale para el bloque del Equipo de Individuación', 'el tramo no filtra Superiores');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal","tramo":"y6_y9"}', '{"tipo":"satisfaccion"}') $$,
  'P0001', 'El tramo de tutoría solo vale para el bloque del Equipo de Individuación', 'ni la satisfacción');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal"}', '{"tipo":"recomendacion"}', '{tramo}') $$,
  'P0001', 'El tramo de tutoría solo vale para el bloque del Equipo de Individuación', 'ni la recomendación');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal"}', '{"tipo":"seleccion","codigo":"test_mas_valorado"}', '{tramo}') $$,
  'P0001', null, 'ni lo más valorado');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal"}', '{"tipo":"bloque","codigo":"reuniones_departamento"}', '{tramo}') $$,
  'P0001', null, 'ni las reuniones de departamento');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal","docente":true}', '{"tipo":"bloque","codigo":"equipo_individualizacion"}', '{tramo}') $$,
  'P0001', 'Los filtros de personal no se combinan: usa uno a la vez', 'el tramo no se combina con otro filtro de personal');
select throws_ok($$ select public.resumen('{"curso":"2000/01","colectivo":"personal","tramo":"y6_y9"}') $$,
  'P0001', null, 'el resumen de personal no admite el tramo');
select throws_ok($$ select public.detalle_preguntas('{"curso":"2000/01","colectivo":"personal","tramo":"y6_y9"}', 'centro') $$,
  'P0001', null, 'el detalle de otro bloque no admite el tramo');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"personas"}', '{tramo}') $$,
  'P0001', 'Dimensión no válida para alumnos: tramo', 'el tramo no existe en alumnos');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal"}', '{"tipo":"bloque","codigo":"equipo_individualizacion","tramos":["y1_y5"]}') $$,
  'P0001', 'Métrica no válida: tramos', 'el cliente no puede pedir conjuntos de tramos');
select throws_ok($$ select public.resultados_profesor('2000/01', (select tres from ids), '{"tipo":"bloque","codigo":"profesorado","grupo_id":1}') $$,
  'P0001', 'Métrica no válida: grupo_id', 'ni claves internas en el informe del profesor');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"bloque","codigo":"profesorado"}', '{docente_atribuido}') $$,
  'P0001', 'Dimensión no válida para alumnos: docente_atribuido', 'la atribución no es una dimensión pública');

-- Jefes de departamento ------------------------------------------------------------------------
select is(jsonb_array_length(public.listar_jefes('2000/01')), 4, 'cuatro jefes de departamento');
select is((select jsonb_array_length(s -> 'unidades') from jsonb_array_elements(public.informe_jefe_departamento('2000/01', (select tres from ids)) -> 'reuniones') s),
  1, 'dos departamentos oficiales que la encuesta junta en una unidad: una sola sección');
select is((public.informe_jefe_departamento('2000/01', (select tres from ids)) -> 'reuniones' -> 0 -> 'total' ->> 'n')::int, 8,
  'esa sección es la de la unidad de la encuesta');
select is(public.informe_jefe_departamento('2000/01', (select dos from ids)) -> 'reuniones' -> 0 ->> 'conjunto', 'true',
  'dos departamentos ocultos por separado (6 por complementaria y 2) se muestran juntos');
select is((public.informe_jefe_departamento('2000/01', (select dos from ids)) -> 'reuniones' -> 0 -> 'total' ->> 'n')::int, 8, 'juntos suman 8 personas');
select is(jsonb_array_length(public.informe_jefe_departamento('2000/01', (select cuatro from ids)) -> 'reuniones'), 2,
  'uno visible y otro oculto: por separado, sin conjunto');
select is((select count(*)::int from jsonb_array_elements(public.informe_jefe_departamento('2000/01', (select cuatro from ids)) -> 'reuniones') s
           where (s ->> 'conjunto')::boolean), 0, 'y nunca juntos');

-- Una sola media de alumnos por jefe, con todos sus departamentos
select is(jsonb_typeof(public.informe_jefe_departamento('2000/01', (select cuatro from ids)) -> 'alumnos'), 'object',
  'la media de alumnos es una sola por jefe, sin desglose por departamento');
select is(public.informe_jefe_departamento('2000/01', (select cuatro from ids)) -> 'alumnos' -> 'departamentos', '["Artes", "Ciencias"]'::jsonb,
  'y abarca todos sus departamentos');
select is(public.informe_jefe_departamento('2000/01', (select cuatro from ids)) -> 'alumnos' -> 'media' -> 'global',
          public.media_departamento_alumnos('2000/01', 'Ciencias') -> 'global',
  'con los docentes de todos sus departamentos (aquí solo Ciencias tiene docentes)');
select is(public.informe_jefe_departamento('2000/01', (select tres from ids)) -> 'alumnos' -> 'media' -> 'global' ->> 'motivo', 'sin_asignacion',
  'un jefe cuyos departamentos no tienen docentes no tiene media');

-- Departamento con todas sus clases compartidas: sin media, pero no por anonimato
set local role postgres;
update public.persona_responsable set departamento_id = (select d.id from public.departamento d join public.curso c on c.id = d.curso_id
  where c.nombre = '2000/01' and d.nombre = 'Letras') where apellidos = 'Tres';
select pg_temp.como('direccion'); set local role authenticated;
select is(public.media_departamento_alumnos('2000/01', 'Letras') -> 'global' ->> 'motivo', 'solo_compartidas',
  'si todas las clases del departamento son compartidas, el motivo es propio (no es anonimato)');
select is(public.media_departamento_alumnos('2000/01', 'Ciencias') -> 'global' ->> 'suprimido', 'false',
  'un departamento con clases propias visibles sigue teniendo media');

-- Clases propias, compartidas y atribuidas ------------------------------------------------------
select is(pg_temp.celda(public.resultados_profesor('2000/01', (select tres from ids)), 'Y7 D', 'Lengua') ->> 'tipo', 'compartida',
  'clase con dos docentes y sin atribución: compartida');
select is(public.resultados_profesor('2000/01', (select tres from ids)) -> 'global' ->> 'motivo', 'sin_combinaciones_visibles',
  'las compartidas no entran en la media global');
select is((public.resultados_profesor('2000/01', (select tres from ids)) ->> 'compartidas')::int, 1, 'y se cuentan aparte');
select is(pg_temp.celda(public.resultados_profesor('2000/01', (select cinco from ids)), 'Y11 A', 'Química') ->> 'tipo', 'atribuida',
  'clase con atribución por nombre: el subconjunto que lo nombró');
select is((pg_temp.celda(public.resultados_profesor('2000/01', (select cinco from ids)), 'Y11 A', 'Química') ->> 'n')::int, 8, 'con sus 8 alumnos');
select is(pg_temp.celda(public.resultados_profesor('2000/01', (select cinco from ids)), 'Y11 B', 'Química') ->> 'motivo', 'complementaria',
  'en Y11 B el otro docente tiene 4 y se oculta; el suyo (6) se oculta por complementaria');
select is((public.resultados_profesor('2000/01', (select cinco from ids)) -> 'global' ->> 'media')::numeric, (select cinco_y11a from ids),
  'la media global usa solo sus subconjuntos visibles');
select is(pg_temp.celda(public.resultados_profesor('2000/01', (select siete from ids)), null, 'Optativa') ->> 'n', '7',
  'optativa atribuida sin asignación por grupo: por cuestionario, sin grupo');
select is((select count(*)::int from jsonb_array_elements(public.resultados_profesor('2000/01', (select siete from ids)) -> 'celdas') c
           where c -> 'clave' ->> 'asignatura' = 'Optativa'), 1, 'la optativa sale una sola vez (todos sus grupos), no también grupo a grupo');
select is((public.resultados_profesor('2000/01', (select siete from ids)) -> 'global' ->> 'n_valoraciones')::int,
          (pg_temp.celda(public.resultados_profesor('2000/01', (select siete from ids)), null, 'Optativa') ->> 'n_valoraciones')::int,
  'y sus valoraciones cuentan una sola vez en la media global');
select ok(exists (select 1 from jsonb_array_elements(public.listar_profesores('2000/01')) p where (p ->> 'id')::int = (select siete from ids)),
  'un docente solo con respuestas atribuidas aparece en la lista de profesores');

select is((pg_temp.celda(public.resultados_profesor('2000/01', (select cuatro from ids)), 'Y7 B', 'Lengua') ->> 'n')::int, 8,
  'la valoración va al profesor que nombraron los alumnos aunque no sea el titular de Alexia');
select is(pg_temp.celda(public.resultados_profesor('2000/01', (select cuatro from ids)), 'Y7 B', 'Lengua') ->> 'tipo', 'atribuida', 'como clase atribuida');
select is(pg_temp.celda(public.resultados_profesor('2000/01', (select dos from ids)), 'Y7 B', 'Lengua'), null,
  'y el titular al que no nombró nadie no la recibe');

-- Profesor con clases en dos cuestionarios, atribuciones en uno y una pregunta que solo existe en
-- el otro: su informe completo no falla (fallo encontrado el 22/10/2026 con los datos reales).
set local role postgres;
do $$
declare
  v_curso smallint := (select id from public.curso where nombre = '2000/01');
  q integer;
begin
  insert into public.pregunta (codigo_diccionario, texto_es, tipo, escala_min, escala_max)
    values ('prof_extra', 'Pregunta solo de PAI', 'escala', 1, 6) returning id into q;
  insert into public.pregunta_cuestionario (cuestionario_id, pregunta_id, bloque_id, orden, por_asignatura)
    select c.id, q, b.id, 3, true from public.cuestionario c join public.bloque b on b.cuestionario_id = c.id and b.codigo = 'profesorado'
    where c.curso_id = v_curso and c.codigo = 'PAI_T';
  insert into public.asignacion_docente (curso_id, grupo_id, asignatura_id, docente_id)
    select v_curso, g.id, a.id, (select siete from ids) from public.grupo g, public.asignatura a
    where g.curso_id = v_curso and g.nombre = 'Y7 C' and a.curso_id = v_curso and a.nombre = 'Lengua';
end $$;
select pg_temp.como('direccion'); set local role authenticated;
select lives_ok($$ select public.informe_profesor('2000/01', (select siete from ids)) $$,
  'el informe de un profesor con atribuciones y preguntas que no están en todos sus cuestionarios no falla');
select is(jsonb_array_length(public.informe_profesor('2000/01', (select siete from ids)) -> 'preguntas'), 3,
  'e incluye todas las preguntas de sus cuestionarios');

-- Coordinación: sin acceso a los informes de responsables
set local role postgres; select pg_temp.como('coord_pai'); set local role authenticated;
select throws_ok($$ select public.listar_jefes('2000/01') $$, '42501', 'Sin acceso a los informes de responsables', 'coordinación: no ve los jefes');
select throws_ok($$ select public.informe_equipo('2000/01', '{y6_y9}') $$, '42501', 'Sin acceso a los informes de responsables', 'ni el Equipo de Individuación');
select throws_ok($$ select public.resultados_profesor('2000/01', (select cinco from ids)) $$, '42501', 'Sin acceso a este profesor',
  'ni profesores de Bachillerato');

select * from finish();
rollback;
