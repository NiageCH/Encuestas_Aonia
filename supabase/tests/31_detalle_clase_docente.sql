-- Detalle de cada pregunta por clase en la versión docente (petición de Mark del 06/11/2026, §7.2): cada celda con el
-- mínimo de 5 y la complementaria; en una clase visible no queda oculta una sola pregunta (se despejaría con la media de
-- la clase); en una clase oculta no se ve ninguna pregunta; la media de cada pregunta, solo con lo visible. La versión
-- completa no cambia.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(32);

set local role postgres;
update privado.configuracion_envio set modo = 'pruebas';
delete from privado.intento_enlace;
create temp table ids as select (select id from public.persona_responsable where apellidos = 'Uno') as uno,
                                (select id from public.curso where nombre = '2000/01') as curso;
grant select on ids to anon, authenticated, service_role;

create function pg_temp.celda(p_inf jsonb, p_pregunta text, p_grupo text) returns jsonb language sql as $$
  select c from jsonb_array_elements(p_inf -> 'preguntas') p, jsonb_array_elements(p -> 'resultado' -> 'celdas') c
  where p ->> 'codigo' = p_pregunta and c -> 'clave' ->> 'grupo' = p_grupo and c -> 'clave' ->> 'asignatura' = 'Matemáticas' $$;
create function pg_temp.global(p_inf jsonb, p_pregunta text) returns jsonb language sql as $$
  select p -> 'resultado' -> 'global' from jsonb_array_elements(p_inf -> 'preguntas') p where p ->> 'codigo' = p_pregunta $$;
grant execute on function pg_temp.celda(jsonb, text, text), pg_temp.global(jsonb, text) to anon, authenticated;

-- 1. El paso por clase, con casos hechos a mano -------------------------------------------------------------------------
create function pg_temp.c(p_g text, p_n integer, p_media numeric, p_tipo text default 'propia') returns jsonb language sql as $$
  select case when p_n is null
    then jsonb_build_object('clave', jsonb_build_object('cuestionario', 'X', 'grupo', p_g, 'asignatura', 'A'),
                            'suprimido', true, 'motivo', 'menos_de_5')
    else jsonb_build_object('clave', jsonb_build_object('cuestionario', 'X', 'grupo', p_g, 'asignatura', 'A'),
                            'suprimido', false, 'n', p_n, 'media', p_media, 'n_valoraciones', p_n)
  end || jsonb_build_object('etapa', 'pai', 'tipo', p_tipo, 'docentes_clase', 1) $$;
create function pg_temp.q(p_codigo text, variadic p_celdas jsonb[]) returns jsonb language sql as $$
  select jsonb_build_object('codigo', p_codigo, 'texto', p_codigo, 'resultado',
    jsonb_build_object('celdas', to_jsonb(p_celdas), 'combinaciones_excluidas', 0, 'global', '{}'::jsonb)) $$;
create function pg_temp.paso(p_bloque jsonb[], variadic p_preg jsonb[]) returns jsonb language sql as $$
  select privado.complementaria_por_clase(jsonb_build_object('celdas', to_jsonb(p_bloque)), to_jsonb(p_preg)) $$;
create function pg_temp.mot(p_paso jsonb, p_codigo text, p_g text) returns text language sql as $$
  select coalesce(c ->> 'motivo', 'visible') from jsonb_array_elements(p_paso) p, jsonb_array_elements(p -> 'resultado' -> 'celdas') c
  where p ->> 'codigo' = p_codigo and c -> 'clave' ->> 'grupo' = p_g $$;

-- Clase G1 visible (10) con tres preguntas, una de ellas con 4: se oculta además la de menos respuestas (7).
create temp table p1 as select pg_temp.paso(array[pg_temp.c('G1', 10, 4), pg_temp.c('G2', 9, 5)],
  pg_temp.q('a', pg_temp.c('G1', null, null), pg_temp.c('G2', 9, 5)),
  pg_temp.q('b', pg_temp.c('G1', 7, 3), pg_temp.c('G2', 9, 5)),
  pg_temp.q('c', pg_temp.c('G1', 10, 4), pg_temp.c('G2', 9, 5))) as r;
select is((select pg_temp.mot(r, 'a', 'G1') from p1), 'menos_de_5', 'una sola pregunta con menos de 5 en la clase: sigue «menos de 5»');
select is((select pg_temp.mot(r, 'b', 'G1') from p1), 'complementaria', '... y se oculta también la de menos respuestas');
select is((select pg_temp.mot(r, 'c', 'G1') from p1), 'visible', '... la otra sigue visible');
select ok((select not (c ? 'n') and not (c ? 'media')
           from p1, jsonb_array_elements(r) p, jsonb_array_elements(p -> 'resultado' -> 'celdas') c
           where p ->> 'codigo' = 'b' and c -> 'clave' ->> 'grupo' = 'G1'), '... sin cifra ni número de respuestas');
select is((select (p -> 'resultado' -> 'global' ->> 'media')::numeric from p1, jsonb_array_elements(r) p where p ->> 'codigo' = 'b'), 5::numeric,
  'la media de la pregunta se calcula otra vez, solo con las clases visibles');
select is((select (p -> 'resultado' -> 'global' ->> 'combinaciones')::int from p1, jsonb_array_elements(r) p where p ->> 'codigo' = 'b'), 1,
  '... y cuenta solo las clases visibles');
select is((select (p -> 'resultado' ->> 'combinaciones_excluidas')::int from p1, jsonb_array_elements(r) p where p ->> 'codigo' = 'b'), 1,
  '... con la oculta entre las excluidas');
select is((select pg_temp.mot(r, 'a', 'G2') || pg_temp.mot(r, 'b', 'G2') || pg_temp.mot(r, 'c', 'G2') from p1), 'visiblevisiblevisible',
  'en una clase sin preguntas ocultas no cambia nada');

-- Dos preguntas ocultas en la clase: ninguna se despeja sola, no hace falta ocultar más.
create temp table p2 as select pg_temp.paso(array[pg_temp.c('G1', 10, 4)],
  pg_temp.q('a', pg_temp.c('G1', null, null)), pg_temp.q('b', pg_temp.c('G1', null, null)), pg_temp.q('c', pg_temp.c('G1', 10, 4))) as r;
select is((select pg_temp.mot(r, 'c', 'G1') from p2), 'visible', 'con dos ocultas en la clase, la tercera se ve');

-- Clase oculta (por complementaria en su tabla) con todas sus preguntas visibles: se ocultan todas.
create temp table p3 as select pg_temp.paso(
  array[jsonb_build_object('clave', jsonb_build_object('cuestionario', 'X', 'grupo', 'G1', 'asignatura', 'A'), 'suprimido', true, 'motivo', 'complementaria')],
  pg_temp.q('a', pg_temp.c('G1', 8, 4)), pg_temp.q('b', pg_temp.c('G1', 9, 3))) as r;
select is((select pg_temp.mot(r, 'a', 'G1') || ' ' || pg_temp.mot(r, 'b', 'G1') from p3), 'complementaria complementaria',
  'clase oculta: no se ve ninguna de sus preguntas (se recompondría su media)');
select is((select p -> 'resultado' -> 'global' ->> 'motivo' from p3, jsonb_array_elements(r) p where p ->> 'codigo' = 'a'), 'sin_combinaciones_visibles',
  '... y sin clases visibles, la pregunta no tiene media');

-- Clase compartida: también se protege, y no entra en la media del docente (como siempre).
create temp table p4 as select pg_temp.paso(array[pg_temp.c('G1', 10, 4), pg_temp.c('G2', 10, 4, 'compartida')],
  pg_temp.q('a', pg_temp.c('G1', 10, 2), pg_temp.c('G2', null, null, 'compartida')),
  pg_temp.q('b', pg_temp.c('G1', 10, 4), pg_temp.c('G2', 6, 3, 'compartida'))) as r;
select is((select pg_temp.mot(r, 'b', 'G2') from p4), 'complementaria', 'clase compartida: el mismo paso');
select is((select (p -> 'resultado' -> 'global' ->> 'media')::numeric from p4, jsonb_array_elements(r) p where p ->> 'codigo' = 'b'), 4::numeric,
  '... sin entrar en la media del docente');

-- 2. Con los datos de ejemplo -------------------------------------------------------------------------------------------
-- En Y7 B, Matemáticas, «Explica con claridad» queda con 4 valoraciones: la clase (8) se ve, esa pregunta no, y «El trato
-- es respetuoso» (8) se despejaría restando: se oculta también.
update privado.respuesta_item ri set valor = null, ns_nc = true
from privado.respuesta r, public.grupo g, public.pregunta p, public.asignatura a
where ri.respuesta_id = r.id and r.grupo_id = g.id and g.nombre = 'Y7 B' and ri.pregunta_id = p.id and p.codigo_diccionario = 'prof_claridad'
  and ri.asignatura_id = a.id and a.nombre = 'Matemáticas' and ri.valor is not null
  and r.id in (select r2.id from privado.respuesta r2 where r2.grupo_id = g.id order by r2.id limit 3);

select pg_temp.como('coord_pai'); set local role authenticated;
create temp table coord as select public.detalle_profesor('2000/01', (select uno from ids)) as r;
select is((select r ->> 'version' from coord), 'docente', 'la coordinación ve en pantalla la versión docente');
select is((select c ->> 'suprimido' from coord, jsonb_array_elements(r -> 'celdas') c where c -> 'clave' ->> 'grupo' = 'Y7 B'), 'false',
  'la clase Y7 B se ve');
select is((select pg_temp.celda(r, 'prof_claridad', 'Y7 B') ->> 'motivo' from coord), 'menos_de_5', 'claridad en Y7 B (4): «menos de 5»');
select is((select pg_temp.celda(r, 'prof_trato', 'Y7 B') ->> 'motivo' from coord), 'complementaria', 'trato en Y7 B (8): complementaria');
select ok((select not (pg_temp.celda(r, 'prof_trato', 'Y7 B') ? 'media') from coord), '... sin cifra');
select is((select pg_temp.global(r, 'prof_trato') ->> 'suprimido' from coord), 'true', 'el trato no tiene ninguna clase visible: sin media');
select is((select pg_temp.celda(r, 'prof_trato', 'Y7 C') ->> 'motivo' from coord), 'menos_de_5', 'Y7 C (3) sigue «menos de 5»');
select is(public.resultados_profesor('2000/01', (select uno from ids), '{"tipo":"pregunta","codigo":"prof_trato"}'),
  (select p -> 'resultado' from coord, jsonb_array_elements(r -> 'preguntas') p where p ->> 'codigo' = 'prof_trato'),
  'la misma pregunta pedida suelta sale igual que en el informe');
select is(public.informe_profesor('2000/01', (select uno from ids), false, 'completa') ->> 'version', 'docente',
  'aunque la coordinación pida la completa, recibe la docente');
set local role postgres;

-- 3. La versión completa no cambia ------------------------------------------------------------------------------------
select pg_temp.como('direccion'); set local role authenticated;
create temp table dir as select public.detalle_profesor('2000/01', (select uno from ids)) as r;
select is((select r ->> 'version' from dir), 'completa', 'Dirección ve en pantalla la versión completa');
select is((select (pg_temp.celda(r, 'prof_claridad', 'Y7 B') ->> 'n')::int from dir), 4, 'con claridad en Y7 B y su n (4)');
select is((select pg_temp.celda(r, 'prof_trato', 'Y7 B') ->> 'suprimido' from dir), 'false', '... y el trato en Y7 B, sin complementaria');
set local role postgres;
select is((select p -> 'resultado' from dir, jsonb_array_elements(r -> 'preguntas') p where p ->> 'codigo' = 'prof_trato'),
  privado.resultados_profesor((select curso from ids), (select uno from ids), '{"tipo":"pregunta","codigo":"prof_trato"}', null),
  'igual que el informe completo de siempre (sin el paso por clase)');
set local role authenticated;
create temp table docente as select public.informe_profesor('2000/01', (select uno from ids), false, 'docente') as r;
select is((select (r -> 'preguntas')::text from docente), (select (r -> 'preguntas')::text from coord),
  'el PDF en versión docente que descarga Dirección: el mismo que ve la coordinación');
set local role postgres;

-- 4. El enlace personal del docente ------------------------------------------------------------------------------------
select pg_temp.como('admin', 'aal2'); set local role authenticated;
create temp table env as select public.admin_envio_crear('2000/01', format('{"tipo":"docente","valores":["%s"]}', (select uno from ids))::jsonb,
  'rodrigo@niage.es') as r;
set local role postgres;
create temp table tok as select p ->> 'token' as token
  from env, jsonb_array_elements(public.envio_pendientes((select (r ->> 'envio')::bigint from env))) p;
grant select on tok, coord to anon;
select set_config('request.jwt.claims', '', true);
set local role anon;
create temp table enl as select public.informe_enlace((select token from tok)) -> 'informe' as r;
select is((select pg_temp.celda(r, 'prof_trato', 'Y7 B') ->> 'motivo' from enl), 'complementaria', 'el enlace trae el detalle por clase con el mismo paso');
select is((select (r -> 'preguntas')::text from enl), (select (r -> 'preguntas')::text from coord), '... igual que la versión docente en pantalla');
set local role postgres;

-- 5. Permisos de la vista nueva -----------------------------------------------------------------------------------------
select pg_temp.como('coord_primaria'); set local role authenticated;
select throws_ok($$ select public.detalle_profesor('2000/01', (select uno from ids)) $$, '42501', null, 'la coordinación de otra etapa no lo ve');
set local role anon;
select throws_ok($$ select public.detalle_profesor('2000/01', 1) $$, '42501', null, 'sin sesión, tampoco');
set local role postgres;
select ok(not has_function_privilege('authenticated', 'privado.complementaria_por_clase(jsonb, jsonb)', 'execute'), 'el paso por clase es interno');

select * from finish();
rollback;
