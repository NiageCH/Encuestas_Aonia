-- Envío de informes al profesorado (§7.10): solo administración, con vista previa; en modo pruebas solo a correos de
-- Niage; enlace personal a la versión docente, con caducidad y cada apertura y descarga registradas.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(29);

set local role postgres;
create temp table ids as select (select id from public.persona_responsable where apellidos = 'Uno') as uno,
                                (select id from public.persona_responsable where apellidos = 'Dos') as dos;
grant select on ids to authenticated, anon;
create temp table tok (token text);
grant all on tok to authenticated, anon, service_role;
update privado.configuracion_envio set modo = 'pruebas';

-- Quién puede
set local role postgres; select pg_temp.como('direccion'); set local role authenticated;
select throws_ok($$ select public.admin_envio_destinatarios('2000/01', '{"tipo":"todos"}', 'rodrigo@niage.es') $$, '42501', null,
  'Dirección no envía informes');
set local role postgres; select pg_temp.como('coord_pai'); set local role authenticated;
select throws_ok($$ select public.admin_envio_crear('2000/01', '{"tipo":"todos"}', 'rodrigo@niage.es') $$, '42501', null, 'la coordinación tampoco');
select ok(not has_function_privilege('authenticated', 'public.envio_pendientes(bigint)', 'execute'), 'los tokens solo los lee la Edge Function');

-- Vista previa (administración)
set local role postgres; select pg_temp.como('admin', 'aal2'); set local role authenticated;
select throws_ok($$ select public.admin_envio_destinatarios('2000/01', '{"tipo":"todos"}') $$, '22023', null,
  'en modo pruebas hace falta un correo de Niage');
select throws_ok($$ select public.admin_envio_destinatarios('2000/01', '{"tipo":"todos"}', 'docente.uno@ejemplo.test') $$, '22023', null,
  'el correo de prueba tiene que ser de Niage');
create temp table prev as select public.admin_envio_destinatarios('2000/01', '{"tipo":"todos"}', 'Rodrigo@niage.es') as r;
select is((select r ->> 'modo' from prev), 'pruebas', 'la vista previa dice el modo');
select is((select jsonb_array_length(r -> 'destinatarios') from prev), 2, 'todos: los dos docentes');
select ok((select bool_and(d ->> 'destinatario' = 'rodrigo@niage.es') from prev, jsonb_array_elements(r -> 'destinatarios') d),
  'en pruebas, todos los correos van al de Niage, ninguno al docente');
select ok((select bool_and(d ->> 'correo' like '%@ejemplo.test') from prev, jsonb_array_elements(r -> 'destinatarios') d),
  '... y la vista previa enseña a quién iría de verdad');
select is(jsonb_array_length(public.admin_envio_destinatarios('2000/01', '{"tipo":"departamento","valores":["Ciencias"]}', 'rodrigo@niage.es') -> 'destinatarios'),
  1, 'por departamento');
select is(jsonb_array_length(public.admin_envio_destinatarios('2000/01', '{"tipo":"etapa","valores":["pai"]}', 'rodrigo@niage.es') -> 'destinatarios'),
  2, 'por etapa');
select is(jsonb_array_length(public.admin_envio_destinatarios('2000/01', '{"tipo":"tramo","valores":["y1_y5"]}', 'rodrigo@niage.es') -> 'destinatarios'),
  0, 'por tramo (Y7 está en Y6 a Y9)');
select is(jsonb_array_length(public.admin_envio_destinatarios('2000/01', '{"tipo":"tramo","valores":["y6_y9"]}', 'rodrigo@niage.es') -> 'destinatarios'),
  2, 'por tramo, Y6 a Y9');
select is(public.admin_envio_destinatarios('2000/01', format('{"tipo":"docente","valores":["%s"]}', (select uno from ids))::jsonb, 'rodrigo@niage.es')
          -> 'destinatarios' -> 0 ->> 'apellidos', 'Uno', 'individual');

-- Modo activo: sin correo de prueba va al docente (cuando exista el remitente del Colegio)
set local role postgres; update privado.configuracion_envio set modo = 'activo'; set local role authenticated;
select is(public.admin_envio_destinatarios('2000/01', format('{"tipo":"docente","valores":["%s"]}', (select uno from ids))::jsonb)
          -> 'destinatarios' -> 0 ->> 'destinatario', 'docente.uno@ejemplo.test', 'en modo activo, al correo del docente');
set local role postgres; update privado.configuracion_envio set modo = 'pruebas'; set local role authenticated;

-- Crear el envío
create temp table env as select public.admin_envio_crear('2000/01', format('{"tipo":"docente","valores":["%s"]}', (select uno from ids))::jsonb,
  'rodrigo@niage.es') as r;
grant select on env to service_role;
select is((select (r ->> 'enlaces')::int from env), 1, 'un enlace por docente');

-- La Edge Function lee el token y lo marca enviado
set local role service_role;
insert into tok select p ->> 'token' from env, jsonb_array_elements(public.envio_pendientes((select (r ->> 'envio')::bigint from env))) p;
select ok((select length(token) >= 40 from tok), 'el token es largo y aleatorio');
set local role postgres;
select is((select count(*)::int from privado.enlace_informe where token_hash = privado.huella((select token from tok))), 1, 'se guarda su huella');
select ok((select caduca between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour' from privado.enlace_informe
           where token_hash = privado.huella((select token from tok))), 'caduca a los 7 días');
set local role service_role;
select public.envio_marcar((select (p ->> 'enlace')::bigint from env, jsonb_array_elements(public.envio_pendientes((select (r ->> 'envio')::bigint from env))) p));
set local role postgres;
select ok((select token is null and enviado is not null from privado.enlace_informe where token_hash = privado.huella((select token from tok))),
  'enviado el correo, el token en claro desaparece');

-- El docente abre el enlace, sin cuenta
set local role anon;
create temp table abre as select public.informe_enlace((select token from tok)) as r;
select is((select r ->> 'estado' from abre), 'ok', 'el enlace abre el informe sin cuenta');
select is((select r -> 'informe' ->> 'version' from abre), 'docente', 'siempre la versión docente');
select ok((select r -> 'informe' -> 'celdas' @? '$[*] ? (@.motivo == "menos_de_5")' from abre),
  '... con el mínimo de 5');
select throws_ok($$ select public.informe_enlace('no-es-un-token-valido-pero-es-bastante-largo-xxxxxxxxxxxx') $$, 'P0002', null, 'un token inventado no abre nada');
select ok((public.descarga_enlace((select token from tok), 'Informe.pdf') ->> 'codigo') ~ '^[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}$',
  'la descarga del PDF da su código');
set local role postgres;
select is((select count(*)::int from privado.apertura_enlace a join privado.enlace_informe e on e.id = a.enlace_id
           where e.token_hash = privado.huella((select token from tok))), 2, 'la apertura y la descarga quedan registradas');
select ok(exists (select 1 from public.registro_actividad where accion = 'descarga' and detalle ->> 'version' = 'docente' and detalle ? 'enlace'
                  and detalle ->> 'nombre' = 'Docente Uno'), 'la descarga está en el registro de descargas, a nombre del docente');

-- Caducado y anulado
update privado.enlace_informe set caduca = now() - interval '1 minute' where token_hash = privado.huella((select token from tok));
set local role anon;
select is(public.informe_enlace((select token from tok)) ->> 'estado', 'caducado', 'pasados los 7 días, caduca');
set local role postgres;
update privado.enlace_informe set caduca = now() + interval '1 day' where token_hash = privado.huella((select token from tok));
select pg_temp.como('admin', 'aal2'); set local role authenticated;
select public.admin_enlace_anular((select (e ->> 'id')::bigint from jsonb_array_elements(public.admin_envios('2000/01')) e limit 1));
set local role anon;
select throws_ok($$ select public.informe_enlace((select token from tok)) $$, 'P0002', null, 'un enlace anulado ya no abre');

select * from finish();
rollback;
