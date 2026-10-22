-- Exportación de cada vista (CSV y PDF): cada exportación queda en el registro de actividad, con
-- la vista, el formato y los filtros, y solo la registra quien puede ver esa vista.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(16);

-- anon
set local role anon;
select throws_ok($$ select public.registrar_exportacion('familias', 'csv', '{}') $$, '42501', null, 'anon no registra exportaciones');

-- Dirección
set local role postgres; select pg_temp.como('direccion'); set local role authenticated;
select lives_ok($$ select public.registrar_exportacion('familias', 'csv', '{"Etapa":"PAI"}') $$, 'dirección exporta familias en CSV');
select lives_ok($$ select public.registrar_exportacion('personal', 'pdf', '{"Personas":"Docentes"}') $$, 'y personal en PDF');
select lives_ok($$ select public.registrar_exportacion('inicio', 'csv', null) $$, 'sin filtros también vale');
select throws_ok($$ select public.registrar_exportacion('familias', 'xlsx', '{}') $$, '22023', 'Formato de exportación no válido',
  'solo CSV y PDF');
select throws_ok($$ select public.registrar_exportacion('profesores', 'csv', '{}') $$, '22023', 'Vista de exportación no válida',
  'solo las vistas con exportación');
select throws_ok($$ select public.registrar_exportacion('familias', 'csv', '["PAI"]') $$, '22023', 'Filtros de exportación no válidos',
  'los filtros son un objeto');
select throws_ok($$ select public.registrar_exportacion('familias', 'csv', jsonb_build_object('x', repeat('a', 3000))) $$, '22023',
  'Filtros de exportación no válidos', 'y de tamaño acotado');
select throws_ok($$ insert into public.registro_actividad (accion) values ('exportacion') $$, '42501', null,
  'nadie escribe la exportación directamente en el registro');

-- Coordinación: su etapa en alumnos y familias, nunca personal
set local role postgres; select pg_temp.como('coord_pai'); set local role authenticated;
select lives_ok($$ select public.registrar_exportacion('alumnos', 'pdf', '{"Grupo":"Y7 A"}') $$, 'coordinación exporta alumnos');
select throws_ok($$ select public.registrar_exportacion('personal', 'csv', '{}') $$, '42501', 'Sin acceso a los resultados de personal',
  'coordinación no exporta personal');

-- Sin acceso
set local role postgres; select pg_temp.como('inactivo'); set local role authenticated;
select throws_ok($$ select public.registrar_exportacion('familias', 'csv', '{}') $$, '42501', 'Sin acceso', 'un usuario desactivado no exporta');
set local role postgres; select pg_temp.como('admin', 'aal1'); set local role authenticated;
select throws_ok($$ select public.registrar_exportacion('familias', 'csv', '{}') $$, '42501', 'Doble factor obligatorio para administradores',
  'un administrador sin doble factor no exporta');

-- Lo que queda en el registro: solo las filas de esta transacción (fecha = now()), porque en la nube
-- el registro ya tiene exportaciones reales.
set local role postgres;
select is((select count(*)::int from public.registro_actividad where accion = 'exportacion' and fecha = now()), 4,
  'quedan registradas las cuatro exportaciones válidas, y ninguna rechazada');
select is((select detalle from public.registro_actividad where accion = 'exportacion' and fecha = now() and detalle ->> 'vista' = 'familias'),
  '{"vista":"familias","formato":"csv","filtros":{"Etapa":"PAI"}}'::jsonb, 'con la vista, el formato y los filtros');
select is((select usuario_id from public.registro_actividad where accion = 'exportacion' and fecha = now() and detalle ->> 'vista' = 'alumnos'),
  '00000000-0000-0000-0000-00000000000c'::uuid, 'y con quien exporta');

select * from finish();
rollback;
