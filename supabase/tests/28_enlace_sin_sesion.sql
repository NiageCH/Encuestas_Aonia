-- Enlace personal sin sesión (§7.10): un enlace caducado o anulado no abre nada; el enlace de un docente no da acceso al
-- informe de otro ni a ninguna otra función; un token alterado o inventado no da acceso; y los intentos al azar quedan
-- limitados.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(42);

set local role postgres;
update privado.configuracion_envio set modo = 'pruebas', intentos_por_minuto = 20;
delete from privado.intento_enlace;
create temp table ids as select (select id from public.persona_responsable where apellidos = 'Uno') as uno,
                                (select id from public.persona_responsable where apellidos = 'Dos') as dos;
create temp table tok (apellidos text, token text);
grant select on ids to anon, authenticated, service_role;
grant all on tok to anon, authenticated, service_role;

-- Un enlace para cada docente (prueba, a un correo de Niage)
select pg_temp.como('admin', 'aal2'); set local role authenticated;
create temp table env as select public.admin_envio_crear('2000/01', '{"tipo":"todos"}', 'rodrigo@niage.es') as r;
grant select on env to service_role;
set local role service_role;
insert into tok select p ->> 'apellidos', p ->> 'token'
  from env, jsonb_array_elements(public.envio_pendientes((select (r ->> 'envio')::bigint from env))) p;
select public.envio_marcar((p ->> 'enlace')::bigint) from env, jsonb_array_elements(public.envio_pendientes((select (r ->> 'envio')::bigint from env))) p;

-- Sin ninguna sesión desde aquí
set local role postgres; select set_config('request.jwt.claims', '', true);
create function pg_temp.t(p_apellidos text) returns text language sql as $$ select token from tok where apellidos = p_apellidos $$;
grant execute on function pg_temp.t(text) to anon;

-- 1. Un enlace caducado o anulado no abre nada ------------------------------------------------------------------------
update privado.enlace_informe set caduca = now() - interval '1 second' where token_hash = privado.huella(pg_temp.t('Dos'));
set local role anon;
create temp table cad as select public.informe_enlace(pg_temp.t('Dos')) as r;
select is((select r ->> 'estado' from cad), 'caducado', 'caducado: lo dice');
select ok((select not (r ? 'informe') and not (r ? 'profesor') from cad), 'caducado: sin informe ni nombre');
select ok(not (public.descarga_enlace(pg_temp.t('Dos'), 'x.pdf') ? 'codigo'), 'caducado: tampoco se descarga el PDF');
set local role postgres;
select is((select count(*)::int from privado.apertura_enlace a join privado.enlace_informe e on e.id = a.enlace_id
           where e.token_hash = privado.huella(pg_temp.t('Dos'))), 0, 'caducado: no cuenta como apertura ni descarga');
update privado.enlace_informe set caduca = now() + interval '1 day', anulado = now() where token_hash = privado.huella(pg_temp.t('Dos'));
set local role anon;
select is(public.informe_enlace(pg_temp.t('Dos')) ->> 'estado', 'no_valido', 'anulado: no abre');
select ok(not (public.informe_enlace(pg_temp.t('Dos')) ? 'informe'), 'anulado: sin informe');
select is(public.descarga_enlace(pg_temp.t('Dos'), 'x.pdf') ->> 'estado', 'no_valido', 'anulado: no se descarga');

-- 2. El enlace de un docente no da acceso al informe de otro ni a ninguna otra función --------------------------------
create temp table uno as select public.informe_enlace(pg_temp.t('Uno')) as r;
select is((select r ->> 'estado' from uno), 'ok', 'el enlace de Uno abre');
select is((select (r -> 'informe' -> 'docente' ->> 'id')::int from uno), (select uno from ids), '... y es el informe de Uno');
select is((select r -> 'profesor' ->> 'apellidos' from uno), 'Uno', '... a su nombre');
select is((select count(*)::int from pg_proc where proname in ('informe_enlace', 'descarga_enlace') and pronamespace = 'public'::regnamespace
           and pronargs <> case proname when 'informe_enlace' then 1 else 2 end), 0,
  'las funciones del enlace solo reciben el token: no se puede pedir a otra persona');
select is(current_setting('encuestas.enlace', true), '', 'después de abrirlo no queda ningún permiso abierto en la sesión');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"personas"}') $$, '42501', null,
  'ni resultados generales');
select throws_ok($$ select public.resultados_profesor('2000/01', (select dos from ids)) $$, '42501', null, 'ni el informe de otro docente');
select throws_ok($$ select public.informe_profesor('2000/01', (select dos from ids)) $$, '42501', null, 'ni su PDF');
select throws_ok($$ select public.listar_profesores('2000/01') $$, '42501', null, 'ni la lista del profesorado');
select throws_ok($$ select public.abiertas('{"curso":"2000/01","colectivo":"alumnos","pregunta":"comentario"}') $$, '42501', null,
  'ni las respuestas abiertas');
select throws_ok($$ select public.admin_envios('2000/01') $$, '42501', null, 'ni los enlaces enviados');
select throws_ok($$ select public.registrar_descarga('csv', '{"objeto":"x","vista":"alumnos","archivo":"x.csv"}') $$, '42501', null,
  'ni otras descargas');
select throws_ok($$ select * from privado.enlace_informe $$, '42501', null, 'ni las tablas de enlaces');
select throws_ok($$ select * from privado.respuesta $$, '42501', null, 'ni las respuestas');
create temp table baja as select public.descarga_enlace(pg_temp.t('Uno'), 'Informe.pdf') as r;
set local role postgres;
select ok(not has_function_privilege('anon', 'privado.informe_profesor(smallint, integer, text)', 'execute')
          and not has_function_privilege('anon', 'privado.exigir_o_enlace()', 'execute')
          and not has_schema_privilege('anon', 'privado', 'usage'),
  'ni las funciones internas que usa el enlace');
create temp table huella as select encode(extensions.digest(pg_temp.t('Uno'), 'sha256'), 'hex') as h;
grant select on huella to anon;
select is((select detalle ->> 'docente' from public.registro_actividad where accion = 'descarga' and detalle ->> 'codigo' = (select r ->> 'codigo' from baja))::int,
  (select uno from ids), 'la descarga queda a nombre de Uno, con su código');
select ok(not exists (select 1 from privado.enlace_informe where token is not null and enviado is not null),
  'enviados los correos, ningún token queda guardado en claro');

-- 3. Un token alterado o inventado no da acceso -----------------------------------------------------------------------
set local role anon;
select is(public.informe_enlace(left(pg_temp.t('Uno'), -1) || case when right(pg_temp.t('Uno'), 1) = 'A' then 'B' else 'A' end) ->> 'estado',
  'no_valido', 'cambiar una letra del token');
select is(public.informe_enlace(left(pg_temp.t('Uno'), 39)) ->> 'estado', 'no_valido', 'token recortado');
select is(public.informe_enlace(pg_temp.t('Uno') || 'x') ->> 'estado', 'no_valido', 'token alargado');
select is(public.informe_enlace(upper(pg_temp.t('Uno'))) ->> 'estado', 'no_valido', 'token en mayúsculas');
select is(public.informe_enlace((select h from huella)) ->> 'estado', 'no_valido', 'la huella guardada no sirve como token');
select is(public.informe_enlace('') ->> 'estado', 'no_valido', 'token vacío');
select is(public.informe_enlace(null) ->> 'estado', 'no_valido', 'sin token');
select is(public.informe_enlace($$x' or '1'='1$$) ->> 'estado', 'no_valido', 'texto con comillas');
select is(public.descarga_enlace('inventado-pero-largo-0123456789012345678901234567890', 'x.pdf') ->> 'estado', 'no_valido',
  'un token inventado tampoco descarga');

-- 4. Los intentos al azar quedan limitados ---------------------------------------------------------------------------
set local role postgres; delete from privado.intento_enlace; set local role anon;
select is((select count(*)::int from generate_series(1, 19) g, lateral (select public.informe_enlace(md5(g::text) || md5(g::text)) as r) x
           where x.r ->> 'estado' = 'no_valido'), 19, '19 intentos al azar en un minuto: rechazados uno a uno');
select is(public.informe_enlace(pg_temp.t('Uno')) ->> 'estado', 'ok', 'por debajo del límite, el enlace bueno sigue abriendo');
select is(public.informe_enlace(md5('veinte') || md5('veinte')) ->> 'estado', 'no_valido', 'el intento 20');
select is(public.informe_enlace(md5('veintiuno') || md5('veintiuno')) ->> 'estado', 'limitado', 'pasado el límite, se corta');
select is(public.informe_enlace(pg_temp.t('Uno')) ->> 'estado', 'limitado', 'durante ese minuto no se abre ningún enlace, ni el bueno');
select is(public.descarga_enlace(pg_temp.t('Uno'), 'x.pdf') ->> 'estado', 'limitado', 'ni se descarga');
set local role postgres;
select is((select count(*)::int from privado.intento_enlace), 20, 'se anotan los intentos fallidos (los cortados no cuentan)');
select is((select array_agg(column_name::text order by column_name) from information_schema.columns
           where table_schema = 'privado' and table_name = 'intento_enlace'), array['fecha', 'id', 'motivo'],
  '... sin IP ni token: solo la hora y el motivo');
update privado.intento_enlace set fecha = now() - interval '2 minutes';
set local role anon;
select is(public.informe_enlace(pg_temp.t('Uno')) ->> 'estado', 'ok', 'pasado el minuto, el enlace bueno vuelve a abrir');

select * from finish();
rollback;
