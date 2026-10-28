-- Criterio de Dirección y administración (§5.0): ven también los resultados de menos de 5, con la marca y su número,
-- sin supresión complementaria. La coordinación y la versión docente del informe siguen con el mínimo de 5.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(30);

create temp table ids as
  select (select id from public.persona_responsable where apellidos = 'Uno') as uno;
grant select on ids to authenticated;

-- Ninguna fila visible con menos de 5 respuestas en todo el JSON (para la coordinación y la versión docente).
create function pg_temp.visibles_menos_5(j jsonb) returns bigint
language sql as $$
  with recursive nodos(x) as (
    select j
    union all
    select v from nodos, lateral (
      select value as v from jsonb_each(case when jsonb_typeof(x) = 'object' then x end)
      union all
      select value from jsonb_array_elements(case when jsonb_typeof(x) = 'array' then x end)
    ) h
  )
  select count(*) from nodos
  where jsonb_typeof(x) = 'object' and x ->> 'suprimido' = 'false' and (x ->> 'n')::numeric < 5;
$$;
create function pg_temp.motivos(j jsonb, m text) returns bigint
language sql as $$
  with recursive nodos(x) as (
    select j
    union all
    select v from nodos, lateral (
      select value as v from jsonb_each(case when jsonb_typeof(x) = 'object' then x end)
      union all
      select value from jsonb_array_elements(case when jsonb_typeof(x) = 'array' then x end)
    ) h
  )
  select count(*) from nodos where jsonb_typeof(x) = 'object' and x ->> 'motivo' = m;
$$;
create function pg_temp.parte(p jsonb, p_clave jsonb) returns jsonb
language sql as $$ select e from jsonb_array_elements(p -> 'partes') e where e -> 'clave' = p_clave $$;
grant execute on function pg_temp.visibles_menos_5(jsonb), pg_temp.motivos(jsonb, text), pg_temp.parte(jsonb, jsonb) to authenticated;

-- Dirección ---------------------------------------------------------------------------------------------
set local role postgres; select pg_temp.como('direccion'); set local role authenticated;
create temp table d_grupos as
  select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"personas"}', '{grupo}') as r;
select is((select pg_temp.parte(r, '{"grupo":"Y7 C"}') ->> 'suprimido' from d_grupos), 'false', 'Dirección ve Y7 C (3)');
select is((select (pg_temp.parte(r, '{"grupo":"Y7 C"}') ->> 'n')::int from d_grupos), 3, '... con su número de respuestas');
select is((select pg_temp.parte(r, '{"grupo":"Y7 C"}') ->> 'menos_de_5' from d_grupos), 'true', '... y la marca «menos de 5»');
select is((select pg_temp.parte(r, '{"grupo":"Y7 D"}') ->> 'suprimido' from d_grupos), 'false', 'sin complementaria: Y7 D (6) se ve');
select ok((select not (pg_temp.parte(r, '{"grupo":"Y7 D"}') ? 'menos_de_5') from d_grupos), 'Y7 D (6) no lleva la marca');

create temp table d_tabla as
  select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"bloque","codigo":"profesorado"}', '{grupo,asignatura}') as r;
select is((select pg_temp.motivos(r, 'complementaria') + pg_temp.motivos(r, 'menos_de_5') from d_tabla), 0::bigint,
  'en la tabla asignatura por grupo no se oculta nada');
select is((select (pg_temp.parte(r, '{"grupo":"Y7 A","asignatura":"Lengua"}') ->> 'n')::int from d_tabla), 4, 'Lengua en Y7 A (4) se ve, con n 4');
select is((public.resultados('{"curso":"2000/01","colectivo":"alumnos","grupo":"Y7 B"}', '{"tipo":"pregunta","codigo":"centro_ambiente"}') -> 'total' ->> 'menos_de_5'),
  'true', 'una pregunta con 4 valoraciones se ve marcada');
select is((public.resultados('{"curso":"2000/01","colectivo":"familias"}', '{"tipo":"pregunta","codigo":"centro_ambiente"}', '{etapa}') -> 'partes')
          @? '$[*] ? (@.clave.etapa == "bachillerato" && @.suprimido == false && @.menos_de_5 == true)', true,
  'familias de Bachillerato (3) se ve marcada');
select ok(jsonb_array_length(public.detalle_preguntas('{"curso":"2000/01","colectivo":"alumnos"}', 'profesorado', '{grupo,asignatura}')) > 0
          and pg_temp.motivos(public.detalle_preguntas('{"curso":"2000/01","colectivo":"alumnos"}', 'profesorado', '{grupo,asignatura}'), 'complementaria') = 0,
  'el detalle por pregunta tampoco oculta nada');

-- Informe del profesor/a: versión completa y versión docente
create temp table d_completo as select public.informe_profesor('2000/01', (select uno from ids)) as r;
select is((select r ->> 'version' from d_completo), 'completa', 'Dirección recibe por defecto la versión completa');
select ok((select pg_temp.visibles_menos_5(r) > 0 from d_completo), 'la versión completa trae clases de menos de 5, a la vista');
select is((select pg_temp.motivos(r, 'menos_de_5') + pg_temp.motivos(r, 'complementaria') from d_completo), 0::bigint,
  'la versión completa no oculta ninguna clase ni pregunta');
select ok((select bool_and(jsonb_array_length(p -> 'resultado' -> 'celdas') = jsonb_array_length(r -> 'celdas'))
           from d_completo, jsonb_array_elements(r -> 'preguntas') p),
  'cada pregunta trae el detalle de cada clase');
select ok((select r ? 'global_docente' from d_completo), 'trae también la media global de la versión docente');

create temp table d_docente as select public.informe_profesor('2000/01', (select uno from ids), false, 'docente') as r;
select is((select r ->> 'version' from d_docente), 'docente', 'Dirección puede sacar la versión docente');
select is((select pg_temp.visibles_menos_5(r) from d_docente), 0::bigint, 'la versión docente no enseña nada de menos de 5');
select ok((select pg_temp.motivos(r, 'menos_de_5') > 0 from d_docente), 'la versión docente oculta lo de menos de 5');
select ok((select not r ? 'global_docente' from d_docente), 'la versión docente no lleva la media de la otra versión');
select is((select r -> 'global' from d_docente), (select r -> 'global_docente' from d_completo),
  'la media global de la versión docente es la que la completa indica como tal');
select is((public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"personas"}', '{grupo}') @? '$.partes[*] ? (@.menos_de_5 == true)'),
  true, 'después de la versión docente, Dirección vuelve a ver lo de menos de 5');
set local role postgres;
select is((select string_agg(detalle ->> 'version', ',' order by detalle ->> 'version') from public.registro_actividad
           where accion = 'informe_profesor' and fecha = now()), 'completa,docente', 'el registro anota qué versión se generó');
set local role authenticated;
select throws_ok($$ select public.informe_profesor('2000/01', (select uno from ids), false, 'otra') $$, '22023', null,
  'una versión desconocida se rechaza');

-- Administración, igual que Dirección
set local role postgres; select pg_temp.como('admin', 'aal2'); set local role authenticated;
select is((public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"personas"}', '{grupo}') @? '$.partes[*] ? (@.clave.grupo == "Y7 C" && @.n == 3)'),
  true, 'administración también ve Y7 C con n 3');

-- Coordinación: siempre con el mínimo de 5, aunque alguien quite el ajuste de la versión docente
set local role postgres; select pg_temp.como('coord_pai'); set local role authenticated;
set local encuestas.version_docente = 'off';
create temp table c_grupos as
  select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"personas"}', '{grupo}') as r;
select is((select pg_temp.parte(r, '{"grupo":"Y7 C"}') ->> 'motivo' from c_grupos), 'menos_de_5', 'la coordinación sigue sin ver Y7 C');
select is((select pg_temp.parte(r, '{"grupo":"Y7 D"}') ->> 'motivo' from c_grupos), 'complementaria', '... y sigue con la complementaria');
select is((select pg_temp.visibles_menos_5(r) from c_grupos), 0::bigint, 'la coordinación no ve nada de menos de 5');
create temp table c_informe as select public.informe_profesor('2000/01', (select uno from ids), false, 'completa') as r;
select is((select r ->> 'version' from c_informe), 'docente', 'la coordinación recibe la versión docente aunque pida la completa');
select is((select pg_temp.visibles_menos_5(r) from c_informe), 0::bigint, '... sin nada de menos de 5');

-- Sin perfil activo, el criterio de Dirección no se aplica
set local role postgres; select pg_temp.como('inactivo');
select is(privado.ve_menos_de_5(), false, 'un acceso desactivado no tiene el criterio de Dirección');

select * from finish();
rollback;
