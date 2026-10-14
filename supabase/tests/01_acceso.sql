-- Acceso: las respuestas individuales nunca se leen desde el cliente, nadie escribe en el
-- registro desde el cliente y las RPC exigen un perfil activo (y aal2 a los administradores).
begin;
\ir fixtures/datos_ejemplo.psql
select plan(22);

-- anon
set local role anon;
select throws_ok($$ select count(*) from privado.respuesta $$, '42501', null, 'anon no lee privado.respuesta');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"personas"}') $$,
  '42501', null, 'anon no puede ejecutar resultados');
select throws_ok($$ select count(*) from public.cuestionario $$, '42501', null, 'anon no ve el catálogo');

-- authenticated con perfil de dirección
reset role; select pg_temp.como('direccion'); set local role authenticated;
select throws_ok($$ select count(*) from privado.respuesta $$, '42501', null, 'dirección no lee privado.respuesta');
select throws_ok($$ select count(*) from privado.respuesta_item $$, '42501', null, 'dirección no lee privado.respuesta_item');
select throws_ok($$ select count(*) from privado.respuesta_opcion $$, '42501', null, 'dirección no lee privado.respuesta_opcion');
select throws_ok($$ select privado.celdas(array[1], '{}', '{"tipo":"personas"}') $$, '42501', null,
  'dirección no llama a las funciones internas');
select throws_ok($$ insert into public.registro_actividad (accion) values ('falsa') $$, '42501', null,
  'nadie inserta en el registro desde el cliente');
select throws_ok($$ insert into public.cuestionario (curso_id, colectivo, codigo, titulo) values (1, 'personal', 'X', 'X') $$,
  '42501', null, 'nadie escribe en el catálogo desde el cliente');
select throws_ok($$ update public.usuario_perfil set rol = 'administrador' $$, '42501', null,
  'nadie se cambia el rol desde el cliente');
select ok((select count(*) from public.cuestionario) > 0, 'un usuario activo lee el catálogo');
select is((select count(*) from public.persona_responsable), 2::bigint, 'dirección ve los profesores');
select is((select count(*) from public.registro_actividad), 0::bigint, 'dirección no ve el registro de actividad');
select is((select count(*) from public.usuario_perfil), 1::bigint, 'dirección solo ve su propio perfil');

-- coordinación: no ve nombres ni correos de profesores en tablas
reset role; select pg_temp.como('coord_pai'); set local role authenticated;
select is((select count(*) from public.persona_responsable), 0::bigint, 'coordinación no lee persona_responsable');

-- sin perfil o inactivo
reset role; select pg_temp.como('sin_perfil'); set local role authenticated;
select throws_ok($$ select public.resumen('{"curso":"2000/01","colectivo":"familias"}') $$, '42501', 'Sin acceso',
  'un usuario sin perfil no obtiene resultados');
select is((select count(*) from public.cuestionario), 0::bigint, 'un usuario sin perfil no ve el catálogo');
reset role; select pg_temp.como('inactivo'); set local role authenticated;
select throws_ok($$ select public.resumen('{"curso":"2000/01","colectivo":"familias"}') $$, '42501', 'Sin acceso',
  'un usuario desactivado no obtiene resultados');

-- administrador: doble factor obligatorio
reset role; select pg_temp.como('admin', 'aal1'); set local role authenticated;
select throws_ok($$ select public.resumen('{"curso":"2000/01","colectivo":"familias"}') $$, '42501',
  'Doble factor obligatorio para administradores', 'un administrador sin aal2 no obtiene resultados');
select is((select count(*) from public.usuario_perfil), 1::bigint,
  'un administrador sin aal2 solo ve su propio perfil (para saber que debe verificar el doble factor)');
reset role; select pg_temp.como('admin', 'aal2'); set local role authenticated;
select lives_ok($$ select public.resumen('{"curso":"2000/01","colectivo":"familias"}') $$,
  'un administrador con aal2 obtiene resultados');
select is((select count(*) from public.usuario_perfil where id::text like '00000000-0000-0000-0000-0000000000%'), 6::bigint,
  'un administrador con aal2 ve todos los perfiles (los de la fixture)');

select * from finish();
rollback;
