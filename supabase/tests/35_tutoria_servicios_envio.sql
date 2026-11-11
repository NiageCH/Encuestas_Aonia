-- Informes de tutoría y de servicios y envío en un paso (§7.12 a §7.14): solo Dirección y administración; la versión del
-- destinatario con el mínimo de 5; el enlace abre solo su informe; responsables de servicio solo por administración; la
-- vista previa avisa de quién se queda fuera, de quién no vería nada y de quién ya lo recibió, y se puede quitar a quien
-- se quiera. Datos inventados (fixtures/datos_ejemplo.psql): en Y7 B, «centro_ambiente» tiene 4 valoraciones válidas.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(47);

set local role postgres;
create temp table ids as select
  (select id from public.curso where nombre = '2000/01') as curso,
  (select id from public.persona_responsable where apellidos = 'Uno') as uno,
  (select id from public.persona_responsable where apellidos = 'Dos') as dos,
  (select id from public.grupo where nombre = 'Y7 A' and curso_id = (select id from public.curso where nombre = '2000/01')) as y7a,
  (select id from public.grupo where nombre = 'Y7 B' and curso_id = (select id from public.curso where nombre = '2000/01')) as y7b,
  (select id from public.grupo where nombre = 'Y7 D' and curso_id = (select id from public.curso where nombre = '2000/01')) as y7d;
grant select on ids to authenticated, anon, service_role;
update privado.configuracion_envio set modo = 'pruebas';

-- Tutoría: Uno tutora Y7 B y Dos Y7 A; Y7 C y Y7 D sin tutor/a. Pregunta del grupo: «centro_ambiente»; referencia del
-- Colegio: «sup_trato» (solo personal).
insert into public.tutoria (curso_id, grupo_id, persona_id) select curso, y7b, uno from ids;
insert into public.tutoria (curso_id, grupo_id, persona_id) select curso, y7a, dos from ids;
insert into public.tutoria_pregunta (curso_id, pregunta_id, ambito, orden)
  select (select curso from ids), id, 'grupo', 1 from public.pregunta where codigo_diccionario = 'centro_ambiente';
insert into public.tutoria_pregunta (curso_id, pregunta_id, ambito, orden)
  select (select curso from ids), id, 'colegio', 1 from public.pregunta where codigo_diccionario = 'sup_trato';
-- Servicios: «Ambiente», con «centro_ambiente» (alumnado, familias y personal), sin responsable; y «Vacío», sin preguntas.
insert into public.servicio (curso_id, codigo, nombre, orden) select curso, 'ambiente', 'Ambiente', 1 from ids;
insert into public.servicio (curso_id, codigo, nombre, orden) select curso, 'vacio', 'Vacío', 2 from ids;
insert into public.servicio_pregunta (servicio_id, pregunta_id, principal)
  select s.id, p.id, true from public.servicio s, public.pregunta p, ids
  where s.codigo = 'ambiente' and s.curso_id = ids.curso and p.codigo_diccionario = 'centro_ambiente';
create temp table srv as select (select s.id from public.servicio s join public.curso c on c.id = s.curso_id where s.codigo = 'ambiente' and c.nombre = '2000/01') as ambiente;
grant select on srv to authenticated, anon, service_role;
create temp table tok (tipo text, token text);
grant all on tok to authenticated, anon, service_role;

-- Quién puede
select pg_temp.como('coord_pai'); set local role authenticated;
select throws_ok($$ select public.listar_tutorias('2000/01') $$, '42501', null, 'la coordinación no ve los informes de tutoría');
select throws_ok($$ select public.informe_tutoria('2000/01', (select y7b from ids), false, 'tutor') $$, '42501', null, '... ni la versión del tutor/a');
select throws_ok($$ select public.listar_servicios('2000/01') $$, '42501', null, 'ni los de servicios');
select throws_ok($$ select public.informe_servicio('2000/01', (select ambiente from srv), false, 'responsable') $$, '42501', null, '... de ninguna versión');
select throws_ok($$ select public.registrar_descarga('informe_tutoria', '{"objeto": "x", "archivo": "x.pdf"}') $$, '42501', null,
  'ni puede descargarlos');
set local role postgres; select pg_temp.como('direccion'); set local role authenticated;
select throws_ok($$ select public.admin_servicio_responsable('2000/01', (select ambiente from srv), 'Ana', 'Ejemplo', 'ana@ejemplo.test') $$,
  '42501', null, 'Dirección no pone responsables de servicio: solo administración');
select throws_ok($$ select public.admin_envio_visibles('2000/01', array['tutoria:1::1:']) $$, '42501', null, 'ni comprueba envíos');
set local role postgres;
select ok(not has_function_privilege('anon', 'public.informe_tutoria(text, integer, boolean, text)', 'execute')
          and not has_function_privilege('anon', 'public.informe_servicio(text, integer, boolean, text)', 'execute')
          and not has_function_privilege('authenticated', 'privado.informe_tutoria(text, integer)', 'execute')
          and not has_function_privilege('authenticated', 'privado.informe_servicio(text, integer)', 'execute'),
  'sin sesión no se piden, y las funciones internas no se llaman desde fuera');
set local role authenticated;
select is((select count(*)::int from public.tutoria where curso_id = (select curso from ids)), 2, 'Dirección lee los tutores');

-- Informe de tutoría: dos versiones
select is(jsonb_array_length(public.listar_tutorias('2000/01')), 4, 'grupos con respuestas o tutor/a');
create temp table tut as select public.informe_tutoria('2000/01', (select y7b from ids)) as c,
                               public.informe_tutoria('2000/01', (select y7b from ids), false, 'tutor') as d;
select is((select c ->> 'version' from tut), 'completa', 'Dirección ve la completa');
select is((select (c -> 'preguntas' -> 0 -> 'grupo' ->> 'n')::int from tut), 4, '... con lo que tiene menos de 5 respuestas');
select is((select (c -> 'preguntas' -> 0 -> 'grupo' ->> 'menos_de_5')::boolean from tut), true, '... marcado');
select is((select d ->> 'version' from tut), 'tutor', 'la versión para el tutor/a');
select is((select d -> 'preguntas' -> 0 -> 'grupo' ->> 'motivo' from tut), 'menos_de_5', '... con el mínimo de 5');
select ok((select not (d @? '$.** ? (@.suprimido == false && @.n < 5)') from tut), '... y nada visible de menos de 5');
set local role postgres; select pg_temp.como('coord_pai'); set local role authenticated;
create temp table coord as select public.resultados('{"curso":"2000/01","colectivo":"alumnos","cuestionario":"PAI_T","grupo":"Y7 B"}',
                                                   '{"tipo":"pregunta","codigo":"centro_ambiente"}') -> 'total' as c;
set local role postgres; select pg_temp.como('direccion'); set local role authenticated;
select is((select d -> 'preguntas' -> 0 -> 'grupo' from tut), (select c from coord),
  'el grupo es la misma celda que ve la coordinación en Alumnado');
select ok((select (d -> 'preguntas' -> 0 -> 'etapa' ->> 'n')::int > 5 from tut), 'la referencia es toda la etapa');
select is((select d -> 'colegio' -> 0 ->> 'colectivo' from tut), 'personal', 'la labor tutorial del personal, como referencia del Colegio');
select is((select jsonb_array_length(public.informe_tutoria('2000/01', (select y7a from ids), false, 'tutor') -> 'preguntas')), 1,
  'en Y7 A, visible');

-- Informe de servicio
create temp table inf_s as select public.informe_servicio('2000/01', (select ambiente from srv), false, 'responsable') as d;
select is((select jsonb_agg(c ->> 'colectivo') from inf_s, jsonb_array_elements(d -> 'colectivos') c), '["alumnos", "familias", "personal"]'::jsonb,
  'un apartado por colectivo');
select ok((select not (d @? '$.** ? (@.suprimido == false && @.n < 5)') from inf_s), 'la versión del responsable, con el mínimo de 5');
select ok((select d @? '$.colectivos[1].preguntas[0].etapas[*] ? (@.clave.etapa == "bachillerato" && @.suprimido == true)' from inf_s),
  'las familias de Bachillerato (3) salen ocultas');
select ok((select not (d @? '$.colectivos[*].preguntas[*].etapas[*] ? (@.clave.etapa == "(sin dato)")') from inf_s),
  'las respuestas sin etapa no salen como una etapa');

-- Responsables de servicio (administración)
set local role postgres; select pg_temp.como('admin', 'aal2'); set local role authenticated;
select throws_ok($$ select public.admin_servicio_responsable('2000/01', (select ambiente from srv), 'Ana', 'Ejemplo', 'no-es-un-correo') $$,
  '22023', null, 'el correo tiene que ser válido');
select throws_ok($$ select public.admin_servicio_responsable('2000/01', (select ambiente from srv), '', '', 'nueva@ejemplo.test') $$,
  '22023', null, 'una persona nueva necesita nombre y apellidos');
select is(public.admin_servicio_responsable('2000/01', (select ambiente from srv), 'Otro', 'Nombre', ' Docente.Uno@Ejemplo.test ') ->> 'apellidos',
  'Uno', 'con el correo de alguien que ya está, se usa esa persona');
select ok(public.admin_servicio_responsable('2000/01', (select ambiente from srv), 'Ana', 'Ejemplo', 'ana.ejemplo@ejemplo.test') ->> 'id' is not null,
  'con un correo nuevo, se crea la persona (personal no docente)');
set local role postgres;
select is((select pr.correo from public.responsable_servicio rs join public.persona_responsable pr on pr.id = rs.persona_id
           where rs.servicio_id = (select ambiente from srv)), 'ana.ejemplo@ejemplo.test',
  'un responsable por servicio: el último');
select is((select count(*)::int from public.registro_actividad where accion = 'responsable_servicio' and detalle ->> 'curso' = '2000/01'), 2,
  'cada cambio queda en el registro');
set local role authenticated;
select throws_ok($$ insert into public.responsable_servicio (servicio_id, persona_id) values ((select ambiente from srv), (select uno from ids)) $$,
  '42501', null, 'nadie escribe la lista directamente');

-- Envío en un paso
create temp table prev_t as select public.admin_envio_destinatarios('2000/01', '{"informe":"tutoria"}', 'rodrigo@niage.es') as r;
select is((select jsonb_agg(d ->> 'informe' order by d ->> 'informe') from prev_t, jsonb_array_elements(r -> 'destinatarios') d),
  '["Y7 A", "Y7 B", "Y7 C", "Y7 D"]'::jsonb, 'tutoría, por defecto todos sus destinatarios: un informe por grupo');
select is((select jsonb_agg(d ->> 'informe' order by d ->> 'informe') from prev_t, jsonb_array_elements(r -> 'destinatarios') d
           where d ->> 'aviso' = 'sin_destinatario'), '["Y7 C", "Y7 D"]'::jsonb, 'los grupos sin tutor/a se quedan fuera, con su aviso');
select is((select jsonb_agg(d ->> 'aviso') from jsonb_array_elements(public.admin_envio_destinatarios('2000/01', '{"informe":"servicio"}', 'rodrigo@niage.es')
           -> 'destinatarios') d where d ->> 'informe' = 'Vacío'), '["sin_destinatario"]'::jsonb, 'un servicio sin responsable, también');
select throws_ok($$ select public.admin_envio_destinatarios('2000/01', '{"informe":"servicio","filtro":{"tipo":"departamento","valores":["Ciencias"]}}', 'rodrigo@niage.es') $$,
  '22023', null, 'cada informe se acota solo por lo suyo');
select is(jsonb_array_length(public.admin_envio_destinatarios('2000/01', '{"tipo":"todos"}', 'rodrigo@niage.es') -> 'destinatarios'), 2,
  'la selección de antes sigue valiendo');
create temp table vis as select public.admin_envio_visibles('2000/01',
  array(select d ->> 'clave' from prev_t, jsonb_array_elements(r -> 'destinatarios') d where d ->> 'aviso' is null order by d ->> 'informe')) as v;
select is((select v from vis), jsonb_build_object(
    format('tutoria:%s::%s:', (select dos from ids), (select y7a from ids)), true,
    format('tutoria:%s::%s:', (select uno from ids), (select y7b from ids)), false),
  'la vista previa sabe quién no vería ningún resultado en su versión (Y7 B)');
create temp table env as select public.admin_envio_crear('2000/01', '{"informe":"tutoria"}', 'rodrigo@niage.es',
  array[format('tutoria:%s::%s:', (select dos from ids), (select y7a from ids))]) as r;
grant select on env to service_role;
select is((select r ->> 'enlaces' from env)::int, 1, 'se envía a los marcados');
select is((select r ->> 'quitados' from env)::int, 1, '... sin los que se quitan en la vista previa');
select is((select r ->> 'fuera' from env)::int, 2, '... ni los que se quedan fuera');

-- La Edge Function lo envía; el tutor/a abre su enlace
set local role service_role;
insert into tok select p ->> 'tipo', p ->> 'token' from env, jsonb_array_elements(public.envio_pendientes((select (r ->> 'envio')::bigint from env))) p;
select is((select p ->> 'grupo' from env, jsonb_array_elements(public.envio_pendientes((select (r ->> 'envio')::bigint from env))) p), 'Y7 B',
  'el correo sabe de qué grupo es');
select public.envio_marcar((select (p ->> 'enlace')::bigint from env, jsonb_array_elements(public.envio_pendientes((select (r ->> 'envio')::bigint from env))) p));
set local role postgres; select set_config('request.jwt.claims', '', true);
set local role anon;
create temp table abre as select public.informe_enlace((select token from tok)) as r;
select is((select r ->> 'tipo' from abre), 'tutoria', 'el enlace abre el informe de tutoría sin cuenta');
select is((select r -> 'informe' -> 'grupo' ->> 'nombre' from abre), 'Y7 B', '... de su grupo');
select is((select r -> 'informe' ->> 'version' from abre), 'tutor', '... en la versión para el tutor/a');
select ok((public.descarga_enlace((select token from tok), 'Informe.pdf') ->> 'codigo') is not null, 'y descarga el PDF');
set local role postgres;
select ok(exists (select 1 from public.registro_actividad where accion = 'descarga' and detalle ->> 'tipo' = 'informe_tutoria'
                  and detalle ->> 'version' = 'tutor' and detalle ->> 'grupo' = 'Y7 B'), 'la descarga queda en el registro, con el grupo');
select pg_temp.como('admin', 'aal2'); set local role authenticated;
select ok((select d ->> 'ya_enviado' is not null from jsonb_array_elements(public.admin_envio_destinatarios('2000/01', '{"informe":"tutoria"}', 'rodrigo@niage.es')
           -> 'destinatarios') d where d ->> 'informe' = 'Y7 B'), 'la vista previa avisa de que ya lo recibió');

select * from finish();
rollback;
