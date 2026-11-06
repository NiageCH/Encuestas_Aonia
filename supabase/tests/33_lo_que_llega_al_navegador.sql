-- Lo que la pantalla no enseña tampoco sale del servidor (revisión del 06/11/2026), con el criterio de la coordinación.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(18);

-- En Y7 B, Matemáticas, 5 alumnos nombran a Uno (el titular) y 3 a un docente sin asignación, Tres (no llega al mínimo).
insert into public.persona_responsable (nombre, apellidos, correo) values ('Docente', 'Tres', 'docente.tres@ejemplo.test');
insert into privado.respuesta_docente (respuesta_id, asignatura_id, docente_id)
  select r.id, a.id, (select id from public.persona_responsable where apellidos = 'Tres')
  from privado.respuesta r join public.grupo g on g.id = r.grupo_id join public.curso cu on cu.id = g.curso_id
  join public.asignatura a on a.curso_id = cu.id and a.nombre = 'Matemáticas'
  where cu.nombre = '2000/01' and g.nombre = 'Y7 B' order by r.id limit 3;
insert into privado.respuesta_docente (respuesta_id, asignatura_id, docente_id)
  select r.id, a.id, (select id from public.persona_responsable where apellidos = 'Uno')
  from privado.respuesta r join public.grupo g on g.id = r.grupo_id join public.curso cu on cu.id = g.curso_id
  join public.asignatura a on a.curso_id = cu.id and a.nombre = 'Matemáticas'
  where cu.nombre = '2000/01' and g.nombre = 'Y7 B' and not exists (select 1 from privado.respuesta_docente x where x.respuesta_id = r.id);
create temp table ids as select (select id from public.persona_responsable where apellidos = 'Uno') as uno,
                                (select id from public.persona_responsable where apellidos = 'Tres') as tres;
grant select on ids to authenticated;
create function pg_temp.docentes_y7b(p_inf jsonb) returns int language sql as $$
  select (c ->> 'docentes_clase')::int from jsonb_array_elements(p_inf -> 'celdas') c
  where c -> 'clave' ->> 'grupo' = 'Y7 B' and c -> 'clave' ->> 'asignatura' = 'Matemáticas' $$;
grant execute on function pg_temp.docentes_y7b(jsonb) to authenticated;

select pg_temp.como('coord_pai'); set local role authenticated;
-- 1. resultados_profesor: solo el bloque del profesorado y sus preguntas
select throws_ok($$ select public.resultados_profesor('2000/01', (select uno from ids), '{"tipo":"satisfaccion"}') $$, '22023', null,
  'resultados_profesor no da la satisfacción general');
select throws_ok($$ select public.resultados_profesor('2000/01', (select uno from ids), '{"tipo":"bloque","codigo":"autoevaluacion"}') $$, '22023', null,
  '... ni otro bloque');
select throws_ok($$ select public.resultados_profesor('2000/01', (select uno from ids), '{"tipo":"pregunta","codigo":"centro_ambiente"}') $$, '22023', null,
  '... ni una pregunta de otro bloque');
select lives_ok($$ select public.resultados_profesor('2000/01', (select uno from ids), '{"tipo":"pregunta","codigo":"prof_trato"}') $$,
  'sí una pregunta del profesorado');

-- 2. La comparación, solo con la media
create temp table coord as select public.detalle_profesor('2000/01', (select uno from ids)) as r;
select ok((select bool_and(k in ('clave', 'media', 'motivo', 'suprimido')) from coord, jsonb_object_keys(r -> 'comparacion' -> 'colegio') k),
  'la comparación con el Colegio lleva solo la media');
select is((select count(*)::int from coord, jsonb_array_elements(r -> 'preguntas') p, jsonb_each(p -> 'resultado' -> 'comparacion') c
           where c.value ?| array['n', 'n_valoraciones', 'n_personas', 'ns_nc', 'distribucion']), 0,
  '... también en cada pregunta: sin número de respuestas ni distribución');

-- 3. Docente nombrado por menos de 5
select ok(not exists (select 1 from jsonb_array_elements(public.listar_profesores('2000/01')) x where (x ->> 'id')::int = (select tres from ids)),
  'no sale en la lista del profesorado');
select ok(not (public.profesores_de_clase('2000/01', '{"cuestionario":"PAI_T","asignatura":"Matemáticas","grupo":"Y7 B"}') @> to_jsonb((select tres from ids))),
  'ni entre los de la clase');
select throws_ok($$ select public.detalle_profesor('2000/01', (select tres from ids)) $$, '42501', null, 'ni se puede abrir su informe');
select is(pg_temp.docentes_y7b((select r from coord)), 1, 'ni cuenta entre los docentes de la clase de Uno');

-- 4. La comparación por recomendación es de Dirección
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"bloque","codigo":"centro"}', '{recomienda}') $$,
  '42501', null, 'la coordinación no pide la comparación por recomendación');

-- 5. Referencia del Colegio en familias
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"familias","referencia":true}', '{"tipo":"seleccion","codigo":"test_mas_valorado"}') $$,
  '22023', null, 'la referencia del Colegio no da la selección múltiple');
select lives_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"familias","referencia":true}', '{"tipo":"satisfaccion"}') $$,
  '... sí la satisfacción');

-- 6. Aspectos con mayor y menor valoración: ninguno oculto
select is((select count(*)::int
           from (select public.puntos_colectivo('{"curso":"2000/01","colectivo":"alumnos"}') as x) y,
                jsonb_array_elements((y.x -> 'mejora') || (y.x -> 'fuertes')) e
           where (public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', jsonb_build_object('tipo', 'pregunta', 'codigo', e ->> 'codigo'))
                  -> 'total' ->> 'suprimido')::boolean), 0, 'los aspectos con mayor y menor valoración no incluyen ninguna pregunta oculta');
set local role postgres;

-- Dirección: todo como antes
select pg_temp.como('direccion'); set local role authenticated;
create temp table dir as select public.detalle_profesor('2000/01', (select uno from ids)) as r;
select ok((select r -> 'comparacion' -> 'colegio' ? 'n' from dir), 'Dirección ve la comparación completa');
select ok(exists (select 1 from jsonb_array_elements(public.listar_profesores('2000/01')) x where (x ->> 'id')::int = (select tres from ids)),
  'Dirección ve al docente nombrado por 3');
select is(pg_temp.docentes_y7b((select r from dir)), 2, '... y lo cuenta en la clase');
select lives_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"bloque","codigo":"centro"}', '{recomienda}') $$,
  'Dirección pide la comparación por recomendación');
set local role postgres;

select * from finish();
rollback;
