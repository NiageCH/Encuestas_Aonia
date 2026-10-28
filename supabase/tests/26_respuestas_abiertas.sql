-- Respuestas abiertas (§7.9): solo Dirección y administración, sueltas (sin enlace con las respuestas cerradas), con los
-- filtros de su colectivo, cada consulta en el registro y la exportación en el registro de descargas.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(24);

set local role postgres;
do $$
declare
  c_pai integer := (select id from public.cuestionario where codigo = 'PAI_T');
  c_fam integer := (select id from public.cuestionario where codigo = 'FAM_T');
  c_per integer := (select id from public.cuestionario where codigo = 'PER_T');
  g_a integer := (select id from public.grupo where nombre = 'Y7 A' and curso_id = (select id from public.curso where nombre = '2000/01'));
  g_b integer := (select id from public.grupo where nombre = 'Y7 B' and curso_id = (select id from public.curso where nombre = '2000/01'));
  p1 integer; p2 integer; p3 integer;
begin
  insert into public.pregunta_abierta (cuestionario_id, orden, codigo, texto) values (c_pai, 1, 'echa_en_falta', '¿Qué echas en falta?') returning id into p1;
  insert into public.pregunta_abierta (cuestionario_id, orden, codigo, texto) values (c_fam, 1, 'comentario', 'Comentarios') returning id into p2;
  insert into public.pregunta_abierta (cuestionario_id, orden, codigo, texto) values (c_per, 1, 'comentario', 'Comentarios') returning id into p3;
  insert into privado.respuesta_abierta (pregunta_id, grupo_id, texto) values
    (p1, g_a, 'Más deporte'), (p1, g_a, 'Una biblioteca más grande'), (p1, g_b, 'Nada');
  insert into privado.respuesta_abierta (pregunta_id, etapas, texto) values
    (p2, '{pai}', 'Gracias'), (p2, '{pai,bachillerato}', 'Más comunicación');
  insert into privado.respuesta_abierta (pregunta_id, docente, antiguedad, texto) values
    (p3, true, 'mas_de_un_ano', 'Comentario de un docente'), (p3, false, 'primer_ano', 'Comentario de no docente');
end $$;
create temp table antes as select (select count(*) from public.registro_actividad where accion = 'abiertas_consulta')::int as n;
grant select on antes to authenticated;

-- Estructura: ninguna columna enlaza con la respuesta cerrada; el cliente no lee las tablas.
select hasnt_column('privado', 'respuesta_abierta', 'respuesta_id', 'una respuesta abierta no apunta a la respuesta cerrada');
select ok(not has_table_privilege('authenticated', 'public.pregunta_abierta', 'select'), 'el cliente no lee pregunta_abierta directamente');
select ok(not has_function_privilege('anon', 'public.abiertas(jsonb)', 'execute'), 'anon no puede pedir respuestas abiertas');

-- Coordinación: nunca
set local role postgres; select pg_temp.como('coord_pai'); set local role authenticated;
select throws_ok($$ select public.abiertas_preguntas('2000/01') $$, '42501', null, 'la coordinación no ve las preguntas abiertas');
select throws_ok($$ select public.abiertas('{"curso":"2000/01","colectivo":"alumnos","pregunta":"echa_en_falta"}') $$, '42501', null,
  'la coordinación no ve las respuestas abiertas, ni de su etapa');
select throws_ok($$ select public.registrar_descarga('csv', '{"objeto": "Respuestas abiertas", "vista": "abiertas", "archivo": "a.csv"}') $$,
  '42501', null, 'la coordinación no puede exportarlas');

-- Dirección
set local role postgres; select pg_temp.como('direccion'); set local role authenticated;
select is(jsonb_array_length(public.abiertas_preguntas('2000/01')), 3, 'Dirección ve las tres preguntas abiertas');
select is((public.abiertas_preguntas('2000/01') -> 0 ->> 'n')::int, 3, '... con su número de respuestas');
create temp table r_alu as select public.abiertas('{"curso":"2000/01","colectivo":"alumnos","pregunta":"echa_en_falta"}') as r;
select is((select (r ->> 'n')::int from r_alu), 3, 'todas las respuestas, también las de un grupo con menos de 5');
select is((select r -> 'respuestas' @? '$[*] ? (@.texto == "Una biblioteca más grande")' from r_alu), true, 'tal cual, sin ocultar nada');
select ok((select bool_and(not (e ?| array['grupo', 'docente', 'antiguedad', 'etapas', 'id'])) from r_alu, jsonb_array_elements(r -> 'respuestas') e),
  'cada respuesta va sin grupo, segmento ni identificador');
select is((public.abiertas('{"curso":"2000/01","colectivo":"alumnos","pregunta":"echa_en_falta","grupo":"Y7 A"}') ->> 'n')::int, 2, 'filtro por grupo');
select is((public.abiertas('{"curso":"2000/01","colectivo":"alumnos","pregunta":"echa_en_falta","etapa":"pai","cuestionario":"PAI_T"}') ->> 'n')::int, 3,
  'filtro por etapa y cuestionario');
select is((public.abiertas('{"curso":"2000/01","colectivo":"familias","pregunta":"comentario","etapa":"bachillerato"}') ->> 'n')::int, 1,
  'familias: filtro por etapa (cuenta en cada etapa que marcó)');
select is((public.abiertas('{"curso":"2000/01","colectivo":"personal","pregunta":"comentario","docente":false}') -> 'respuestas' -> 0 ->> 'texto'),
  'Comentario de no docente', 'personal: filtro docente o no docente');
select is((public.abiertas('{"curso":"2000/01","colectivo":"personal","pregunta":"comentario","antiguedad":"mas_de_un_ano"}') ->> 'n')::int, 1,
  'personal: filtro de antigüedad');
select throws_ok($$ select public.abiertas('{"curso":"2000/01","colectivo":"personal","pregunta":"comentario","docente":true,"antiguedad":"primer_ano"}') $$,
  '22023', null, 'los filtros de personal no se combinan');
select throws_ok($$ select public.abiertas('{"curso":"2000/01","colectivo":"familias","pregunta":"comentario","grupo":"Y7 A"}') $$,
  '22023', null, 'un filtro de otro colectivo se rechaza');
select is(public.abiertas_grupos('2000/01', 'PAI_T'), '["Y7 A", "Y7 B"]'::jsonb, 'grupos con respuestas, para el filtro');
select lives_ok($$ select public.registrar_descarga('csv', '{"objeto": "Respuestas abiertas", "vista": "abiertas", "archivo": "a.csv"}') $$,
  'Dirección puede exportarlas (queda en el registro de descargas)');

-- Administración
set local role postgres; select pg_temp.como('admin', 'aal2'); set local role authenticated;
select is((public.abiertas('{"curso":"2000/01","colectivo":"familias","pregunta":"comentario"}') ->> 'n')::int, 2, 'administración también las ve');

-- Registro: cada consulta
set local role postgres;
select is((select count(*)::int from public.registro_actividad where accion = 'abiertas_consulta') - (select n from antes), 7,
  'cada consulta queda en el registro de actividad');
select is((select detalle -> 'filtro' ->> 'grupo' from public.registro_actividad where accion = 'abiertas_consulta' and detalle -> 'filtro' ? 'grupo'
           order by id desc limit 1), 'Y7 A', '... con sus filtros');
select ok(not exists (select 1 from public.registro_actividad where accion = 'abiertas_consulta' and detalle::text like '%biblioteca%'),
  'el registro no copia ningún texto de respuesta');

select * from finish();
rollback;
