-- Eliminar usuarios: solo administración con doble factor, confirmación con el correo, nunca a uno mismo ni al último
-- administrador, y el registro de actividad conserva las acciones pasadas con el nombre y el correo.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(24);

-- Historial previo de Dirección y una invitación pendiente de Coord PAI
insert into public.registro_actividad (usuario_id, accion, detalle, fecha) values
  ('00000000-0000-0000-0000-00000000000b', 'exportacion', '{"vista":"familias","formato":"csv"}', now() - interval '2 days'),
  ('00000000-0000-0000-0000-00000000000b', 'informe_profesor', '{}', now() - interval '1 day'),
  ('00000000-0000-0000-0000-00000000000a', 'invitacion', '{"usuario":"00000000-0000-0000-0000-00000000000c","nombre":"Coord PAI"}', now() - interval '3 days');
insert into auth.sessions (id, user_id) values (gen_random_uuid(), '00000000-0000-0000-0000-00000000000b');
insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
  values (gen_random_uuid(), '00000000-0000-0000-0000-00000000000b', 'x', 'totp', 'verified', now(), now());
insert into auth.one_time_tokens (id, user_id, token_type, token_hash, relates_to)
  values (gen_random_uuid(), '00000000-0000-0000-0000-00000000000c', 'confirmation_token', 'h', 'coord.pai@ejemplo.test');

-- Permisos
select pg_temp.como('direccion'); set local role authenticated;
select throws_ok($$ select public.admin_eliminar_usuario('00000000-0000-0000-0000-00000000000c', 'coord.pai@ejemplo.test') $$,
  '42501', 'Solo para administradores', 'dirección no puede eliminar');
set local role postgres; select pg_temp.como('coord_pai'); set local role authenticated;
select throws_ok($$ select public.admin_eliminar_usuario('00000000-0000-0000-0000-00000000000b', 'direccion@ejemplo.test') $$,
  '42501', 'Solo para administradores', 'coordinación tampoco');
set local role postgres; select pg_temp.como('admin', 'aal1'); set local role authenticated;
select throws_ok($$ select public.admin_eliminar_usuario('00000000-0000-0000-0000-00000000000b', 'direccion@ejemplo.test') $$,
  '42501', 'Doble factor obligatorio para administradores', 'un administrador sin doble factor tampoco');
set local role anon;
select throws_ok($$ select public.admin_eliminar_usuario('00000000-0000-0000-0000-00000000000b', 'direccion@ejemplo.test') $$,
  '42501', null, 'sin sesión, ni siquiera se puede llamar');

-- Reglas
set local role postgres; select pg_temp.como('admin', 'aal2'); set local role authenticated;
select throws_ok($$ select public.admin_eliminar_usuario('00000000-0000-0000-0000-00000000000a', 'admin@ejemplo.test') $$,
  'P0001', 'No puedes eliminarte a ti mismo', 'nadie se elimina a sí mismo');
select throws_ok($$ select public.admin_eliminar_usuario('00000000-0000-0000-0000-00000000000b', 'otro@ejemplo.test') $$,
  '22023', 'El correo escrito no coincide con el del usuario: no se ha eliminado', 'hay que escribir el correo exacto');
select throws_ok($$ select public.admin_eliminar_usuario('00000000-0000-0000-0000-00000000000b', null) $$,
  '22023', null, 'sin correo, no se elimina');
select throws_ok($$ select public.admin_eliminar_usuario(gen_random_uuid(), 'x@ejemplo.test') $$,
  'P0002', 'Usuario no encontrado', 'usuario que no existe');

set local role postgres;
-- La relación del registro con el usuario no es en cascada
select is((select confdeltype::text from pg_constraint where conrelid = 'public.registro_actividad'::regclass and contype = 'f'), 'n',
  'la relación del registro de actividad con el usuario pasa a nulo al borrarlo (no en cascada)');
-- Dirección también es destinataria: Admin la desactivó y la reactivó
insert into public.registro_actividad (usuario_id, accion, detalle, fecha) values
  ('00000000-0000-0000-0000-00000000000a', 'desactivacion', '{"usuario":"00000000-0000-0000-0000-00000000000b","nombre":"Dirección"}', now() - interval '4 days');
create temp table antes as select id, accion, usuario_id from public.registro_actividad;
grant select on antes to authenticated;
set local role authenticated;

-- Eliminar a Dirección (correo con mayúsculas y espacios)
select lives_ok($$ select public.admin_eliminar_usuario('00000000-0000-0000-0000-00000000000b', '  Direccion@Ejemplo.TEST ') $$,
  'un administrador elimina a otro usuario escribiendo su correo');
set local role postgres;
select is((select count(*)::int from auth.users where id = '00000000-0000-0000-0000-00000000000b'), 0, 'se borra la cuenta de acceso');
select is((select count(*)::int from public.usuario_perfil where id = '00000000-0000-0000-0000-00000000000b'), 0, 'y su perfil');
select is((select count(*)::int from auth.sessions where user_id = '00000000-0000-0000-0000-00000000000b')
        + (select count(*)::int from auth.mfa_factors where user_id = '00000000-0000-0000-0000-00000000000b'), 0,
  'y sus sesiones abiertas y su doble factor');
select is((select count(*)::int from public.registro_actividad where usuario_nombre = 'Dirección' and usuario_correo = 'direccion@ejemplo.test'), 2,
  'sus acciones pasadas siguen en el registro, con su nombre y correo');
select is((select count(*)::int from antes where not exists (select 1 from public.registro_actividad r where r.id = antes.id)), 0,
  'no desaparece ninguna entrada del registro al eliminar');
select is((select count(*)::int from public.registro_actividad) - (select count(*)::int from antes), 1, 'solo se añade la entrada de la eliminación');
select is((select detalle ->> 'nombre' || ' ' || (detalle ->> 'correo') from public.registro_actividad where accion = 'desactivacion' and detalle ->> 'usuario' = '00000000-0000-0000-0000-00000000000b'),
  'Dirección direccion@ejemplo.test', 'como destinataria, la entrada conserva su nombre y gana su correo');
select pg_temp.como('admin', 'aal2'); set local role authenticated;
select is((select string_agg(e ->> 'usuario' || ':' || (e ->> 'usuario_eliminado'), ',' order by e ->> 'accion')
           from jsonb_array_elements(public.admin_registro()) e where e ->> 'accion' in ('exportacion', 'informe_profesor') and e ->> 'usuario' = 'Dirección'),
  'Dirección:true,Dirección:true', 'el registro las muestra a su nombre, marcadas como de un usuario eliminado');
select is((select e -> 'detalle' ->> 'correo' || ' por ' || (e ->> 'usuario') from jsonb_array_elements(public.admin_registro()) e where e ->> 'accion' = 'eliminacion' and e -> 'detalle' ->> 'usuario' = '00000000-0000-0000-0000-00000000000b'),
  'direccion@ejemplo.test por Admin', 'la eliminación queda anotada con el correo y quién la hizo');

-- Invitación pendiente: queda anulada
select lives_ok($$ select public.admin_eliminar_usuario('00000000-0000-0000-0000-00000000000c', 'coord.pai@ejemplo.test') $$,
  'eliminar a quien tiene una invitación pendiente');
set local role postgres;
select is((select count(*)::int from auth.one_time_tokens where user_id = '00000000-0000-0000-0000-00000000000c'), 0,
  'el código de su invitación deja de existir');
select is((select detalle ->> 'nombre' from public.registro_actividad where accion = 'invitacion' and detalle ->> 'usuario' = '00000000-0000-0000-0000-00000000000c'), 'Coord PAI',
  'la invitación que se le envió sigue en el registro');
select is((select (detalle ->> 'correo') || ' por ' || coalesce(usuario_id::text, '?') from public.registro_actividad where accion = 'invitacion' and detalle ->> 'usuario' = '00000000-0000-0000-0000-00000000000c'),
  'coord.pai@ejemplo.test por 00000000-0000-0000-0000-00000000000a', '«Admin invitó a Coord PAI»: tras eliminar a Coord PAI, conserva su nombre y correo, y el autor sigue siendo Admin');

-- Último administrador activo: con otro administrador, se puede eliminar; la regla protege al que queda
insert into auth.users (id, email, aud, role) values ('00000000-0000-0000-0000-0000000000aa', 'admin2@ejemplo.test', 'authenticated', 'authenticated');
insert into public.usuario_perfil (id, nombre, rol, activo) values ('00000000-0000-0000-0000-0000000000aa', 'Admin 2', 'administrador', true);
select pg_temp.como('admin', 'aal2'); set local role authenticated;
select lives_ok($$ select public.admin_eliminar_usuario('00000000-0000-0000-0000-0000000000aa', 'admin2@ejemplo.test') $$,
  'con dos administradores activos, uno puede eliminar al otro (y el que queda no puede eliminarse a sí mismo)');

select * from finish();
rollback;
