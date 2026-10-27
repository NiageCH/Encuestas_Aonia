-- Administración de usuarios (§7.5): solo administradores con doble factor; cambios de rol,
-- desactivar y reactivar con registro; último acceso y aviso a los 90 días.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(17);

create function pg_temp.usuario(p_lista jsonb, p_correo text) returns jsonb
language sql as $$ select e from jsonb_array_elements(p_lista) e where e ->> 'correo' = p_correo $$;
grant execute on function pg_temp.usuario(jsonb, text) to authenticated;

-- Último acceso: el disparador lo copia de auth.users (dirección entró hace 100 días)
update auth.users set last_sign_in_at = now() - interval '100 days' where email = 'direccion@ejemplo.test';
select ok((select ultimo_acceso is not null from public.usuario_perfil where id = '00000000-0000-0000-0000-00000000000b'),
  'el último acceso se copia al perfil al iniciar sesión');

-- Permisos
set local role postgres; select pg_temp.como('direccion'); set local role authenticated;
select throws_ok($$ select public.admin_usuarios() $$, '42501', 'Solo para administración', 'dirección no administra usuarios');
select throws_ok($$ select public.admin_registrar_invitacion('00000000-0000-0000-0000-00000000000b', gen_random_uuid(), 'X', 'direccion', null) $$,
  '42501', null, 'el alta de perfiles solo la hace la Edge Function (clave de servicio)');
set local role postgres; select pg_temp.como('admin', 'aal1'); set local role authenticated;
select throws_ok($$ select public.admin_usuarios() $$, '42501', 'Doble factor obligatorio para las cuentas de administración', 'un administrador sin aal2 tampoco');

-- Lista
set local role postgres; select pg_temp.como('admin', 'aal2'); set local role authenticated;
create temp table lista as select public.admin_usuarios() as l;
select is((select pg_temp.usuario(l, 'coord.pai@ejemplo.test') ->> 'estado' from lista), 'pendiente', 'un invitado que no ha entrado está pendiente');
select is((select pg_temp.usuario(l, 'inactivo@ejemplo.test') ->> 'estado' from lista), 'desactivado', 'estado desactivado');
select is((select pg_temp.usuario(l, 'direccion@ejemplo.test') ->> 'estado' from lista), 'activo', 'quien ya entró está activo');
select is((select pg_temp.usuario(l, 'direccion@ejemplo.test') ->> 'aviso_90_dias' from lista), 'true', 'aviso a los 90 días sin entrar');

-- Cambios con registro
select lives_ok($$ select public.admin_actualizar_usuario('00000000-0000-0000-0000-00000000000c', 'direccion', null, true) $$,
  'cambiar el rol de coordinación a dirección');
select lives_ok($$ select public.admin_actualizar_usuario('00000000-0000-0000-0000-00000000000b', 'direccion', null, false) $$, 'desactivar');
select lives_ok($$ select public.admin_actualizar_usuario('00000000-0000-0000-0000-00000000000b', 'direccion', null, true) $$, 'reactivar');
select is((select string_agg(e ->> 'accion', ',' order by e ->> 'accion') from jsonb_array_elements(public.admin_registro()) e
           where (e ->> 'fecha')::timestamptz = now()),
  'cambio_rol,desactivacion,reactivacion', 'cada cambio queda en el registro de actividad');
select is((select e ->> 'usuario' from jsonb_array_elements(public.admin_registro()) e where (e ->> 'fecha')::timestamptz = now() limit 1), 'Admin',
  'el registro muestra quién hizo el cambio');

-- Reglas
select throws_ok($$ select public.admin_actualizar_usuario('00000000-0000-0000-0000-00000000000a', 'administrador', null, false) $$,
  'P0001', 'No puedes quitarte el rol de administración ni desactivar tu propio acceso', 'un administrador no se desactiva a sí mismo');
select throws_ok($$ select public.admin_actualizar_usuario('00000000-0000-0000-0000-00000000000a', 'direccion', null, true) $$,
  'P0001', 'No puedes quitarte el rol de administración ni desactivar tu propio acceso', 'ni se quita el rol de administrador');
select throws_ok($$ select public.admin_actualizar_usuario('00000000-0000-0000-0000-00000000000d', 'coordinacion', null, true) $$,
  'P0001', 'La coordinación necesita etapa, y los demás roles no la llevan', 'la coordinación necesita etapa');

-- Un usuario desactivado no obtiene resultados (aunque pueda autenticarse)
set local role postgres; select pg_temp.como('inactivo'); set local role authenticated;
select throws_ok($$ select public.resumen('{"curso":"2000/01","colectivo":"familias"}') $$, '42501', 'Sin acceso',
  'un usuario desactivado no ve resultados');

select * from finish();
rollback;
