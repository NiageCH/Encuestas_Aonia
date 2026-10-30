-- Navegar al detalle al pulsar (30/10/2026): cada pantalla de destino respeta el criterio de cada rol (§5.0). Dirección y
-- administración llegan también a lo de menos de 5, marcado y sin complementaria; la coordinación, con el mínimo de 5 y la
-- complementaria, y nunca a pantallas de otro rol. Y la lista del profesorado de una asignatura (profesores_de_clase).
begin;
\ir fixtures/datos_ejemplo.psql
select plan(24);

create temp table ids as
  select (select id from public.persona_responsable where apellidos = 'Uno') as uno,
         (select id from public.persona_responsable where apellidos = 'Dos') as dos;
grant select on ids to authenticated;

-- Profesorado de una asignatura (Alumnado › Profesorado por asignatura → Informes del profesorado)
select ok(not has_function_privilege('anon', 'public.profesores_de_clase(text, jsonb)', 'execute'), 'sin sesión no se puede pedir');
set local role postgres; select pg_temp.como('direccion'); set local role authenticated;
select is(public.profesores_de_clase('2000/01', '{"cuestionario":"PAI_T","asignatura":"Matemáticas"}'),
  (select jsonb_build_array(uno) from ids), 'Matemáticas en PAI_T: Docente Uno');
select is(public.profesores_de_clase('2000/01', '{"cuestionario":"PAI_T","asignatura":"Lengua","grupo":"Y7 B"}'),
  (select jsonb_build_array(dos) from ids), 'Lengua en Y7 B: Docente Dos');
select is(public.profesores_de_clase('2000/01', '{"cuestionario":"PAI_T","asignatura":"Lengua","grupo":"Y7 A"}'), '[]'::jsonb,
  'nadie da Lengua en Y7 A');
select throws_ok($$ select public.profesores_de_clase('2000/01', '{"asignatura":"Lengua"}') $$, '22023', null,
  'sin cuestionario se rechaza');
select ok(not (public.profesores_de_clase('2000/01', '{"cuestionario":"PAI_T","asignatura":"Matemáticas"}')::text ~ 'media|n_'),
  'devuelve solo identificadores, ningún resultado');

set local role postgres; select pg_temp.como('coord_pai'); set local role authenticated;
select is(public.profesores_de_clase('2000/01', '{"cuestionario":"PAI_T","asignatura":"Matemáticas"}'),
  (select jsonb_build_array(uno) from ids), 'la coordinación de PAI, los de su etapa');
set local role postgres; select pg_temp.como('coord_primaria'); set local role authenticated;
select is(public.profesores_de_clase('2000/01', '{"cuestionario":"PAI_T","asignatura":"Matemáticas"}'), '[]'::jsonb,
  'la coordinación de otra etapa no recibe a nadie');
set local role postgres; select pg_temp.como('inactivo'); set local role authenticated;
select throws_ok($$ select public.profesores_de_clase('2000/01', '{"cuestionario":"PAI_T","asignatura":"Matemáticas"}') $$, '42501', null,
  'una cuenta inactiva no puede pedirla');

-- Alumnado › Satisfacción general por grupo → el grupo (filtro en la misma pantalla)
set local role postgres; select pg_temp.como('direccion'); set local role authenticated;
create temp table dir_grupos as
  select public.resultados('{"curso":"2000/01","colectivo":"alumnos","cuestionario":"PAI_T"}', '{"tipo":"bloque","codigo":"general"}', '{grupo}') as r;
select is((select (p ->> 'menos_de_5')::boolean from dir_grupos, jsonb_array_elements(r -> 'partes') p where p -> 'clave' ->> 'grupo' = 'Y7 C'),
  true, 'Dirección: Y7 C (3 respuestas) se ve, marcado «menos de 5»');
select is((select (p ->> 'suprimido')::boolean from dir_grupos, jsonb_array_elements(r -> 'partes') p where p -> 'clave' ->> 'grupo' = 'Y7 D'),
  false, 'Dirección: Y7 D se ve (sin complementaria)');
select is((public.detalle_preguntas('{"curso":"2000/01","colectivo":"alumnos","cuestionario":"PAI_T","grupo":"Y7 C"}', 'centro')
           -> 0 -> 'resultado' -> 'total' ->> 'menos_de_5')::boolean, true,
  'Dirección: el detalle por pregunta de Y7 C se ve, marcado');

set local role postgres; select pg_temp.como('coord_pai'); set local role authenticated;
create temp table coord_grupos as
  select public.resultados('{"curso":"2000/01","colectivo":"alumnos","cuestionario":"PAI_T"}', '{"tipo":"bloque","codigo":"general"}', '{grupo}') as r;
select is((select p ->> 'motivo' from coord_grupos, jsonb_array_elements(r -> 'partes') p where p -> 'clave' ->> 'grupo' = 'Y7 C'),
  'menos_de_5', 'coordinación: Y7 C oculto (menos de 5)');
select is((select p ->> 'motivo' from coord_grupos, jsonb_array_elements(r -> 'partes') p where p -> 'clave' ->> 'grupo' = 'Y7 D'),
  'complementaria', 'coordinación: Y7 D oculto por complementaria');
select is((public.detalle_preguntas('{"curso":"2000/01","colectivo":"alumnos","cuestionario":"PAI_T","grupo":"Y7 C"}', 'centro')
           -> 0 -> 'resultado' -> 'total' ->> 'suprimido')::boolean, true,
  'coordinación: el detalle por pregunta de Y7 C sigue oculto aunque se pida por la dirección de la página');
-- En «general» todos contestan: solo Y7 C queda por debajo de 5 y Y7 D se oculta para no deducirlo por resta.
select is((public.detalle_preguntas('{"curso":"2000/01","colectivo":"alumnos","cuestionario":"PAI_T","grupo":"Y7 D"}', 'general')
           -> 0 -> 'resultado' -> 'total' ->> 'suprimido')::boolean, true,
  'coordinación: tampoco el de Y7 D (complementaria)');

-- Familias › por etapa → la etapa
set local role postgres; select pg_temp.como('direccion'); set local role authenticated;
select is((public.resultados('{"curso":"2000/01","colectivo":"familias","etapa":"bachillerato"}', '{"tipo":"personas"}') -> 'total' ->> 'menos_de_5')::boolean,
  true, 'Dirección: Bachillerato (3 familias) se ve, marcado');
set local role postgres; select pg_temp.como('coord_pai'); set local role authenticated;
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"familias","etapa":"bachillerato"}', '{"tipo":"personas"}') $$,
  '42501', null, 'la coordinación de PAI no llega a otra etapa por la dirección de la página');

-- Personal › docentes, no docentes y departamentos → solo Dirección y administración
set local role postgres; select pg_temp.como('direccion'); set local role authenticated;
select is((public.resultados('{"curso":"2000/01","colectivo":"personal","docente":false}', '{"tipo":"personas"}') -> 'total' ->> 'menos_de_5')::boolean,
  true, 'Dirección: no docentes (4) se ve, marcado');
select ok(jsonb_array_length(public.listar_jefes('2000/01')) > 0, 'Dirección: la lista de jefaturas para ir al departamento');
set local role postgres; select pg_temp.como('coord_pai'); set local role authenticated;
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal","docente":false}', '{"tipo":"personas"}') $$,
  '42501', null, 'la coordinación no ve Personal');
select throws_ok($$ select public.listar_jefes('2000/01') $$, '42501', null, 'ni las jefaturas');
select throws_ok($$ select public.informe_jefe_departamento('2000/01', (select uno from ids)) $$, '42501', null,
  'ni el informe de un departamento');

-- Administración, como Dirección
set local role postgres; select pg_temp.como('admin', 'aal2'); set local role authenticated;
select is(public.profesores_de_clase('2000/01', '{"cuestionario":"PAI_T","asignatura":"Matemáticas"}'),
  (select jsonb_build_array(uno) from ids), 'administración, la misma lista que Dirección');

select * from finish();
rollback;
