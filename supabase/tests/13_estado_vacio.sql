-- Estado vacío fiable: «¿hay resultados cargados?» distingue «no hay datos» de «no tienes acceso» (26/10/2026).
begin;
\ir fixtures/datos_ejemplo.psql
select plan(8);

set local role postgres; select pg_temp.como('direccion'); set local role authenticated;
select is(public.colectivos_cargados('2000/01'), array['alumnos', 'familias', 'personal'], 'dirección: los colectivos con encuestas del curso');
select is(public.colectivos_cargados('1999/00'), '{}'::text[], 'un curso sin encuestas: lista vacía (aquí sí es «no hay datos»)');

-- Administrador cuya sesión todavía no ha pasado el doble factor: error, nunca una lista vacía
set local role postgres; select pg_temp.como('admin', 'aal1'); set local role authenticated;
select throws_ok($$ select public.colectivos_cargados('2000/01') $$, '42501', 'Doble factor obligatorio para las cuentas de administración',
  'un administrador sin doble factor recibe un error, no «sin datos»');
select is((select count(*)::int from public.cuestionario), 0, '(la lectura directa del catálogo le da una lista vacía, que era lo que confundía)');
set local role postgres; select pg_temp.como('admin', 'aal2'); set local role authenticated;
select is(cardinality(public.colectivos_cargados('2000/01')), 3, 'con el doble factor, ve los colectivos');

set local role postgres; select pg_temp.como('inactivo'); set local role authenticated;
select throws_ok($$ select public.colectivos_cargados('2000/01') $$, '42501', 'Sin acceso', 'un usuario desactivado recibe un error');
set local role postgres; select pg_temp.como('sin_perfil'); set local role authenticated;
select throws_ok($$ select public.colectivos_cargados('2000/01') $$, '42501', 'Sin acceso', 'y uno sin perfil también');
set local role anon;
select throws_ok($$ select public.colectivos_cargados('2000/01') $$, '42501', null, 'anon no puede llamarla');

select * from finish();
rollback;
