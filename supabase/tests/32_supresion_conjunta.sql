-- Supresión complementaria conjunta (§5, 06/11/2026): la coordinación no puede despejar una celda oculta comparando la
-- tabla de un bloque con las de sus preguntas (ni con la satisfacción general), ni con los márgenes de una tabla.
-- El test lo intenta con todas las tablas que puede pedir y comprueba que con el motor anterior sí se podía.
begin;
\ir fixtures/datos_ejemplo.psql
\ir fixtures/deducibles.psql
select plan(16);

-- En Y7 B, Matemáticas, «Explica con claridad» queda con 4 valoraciones: la clase (8) se ve, esa pregunta no.
update privado.respuesta_item set valor = null, ns_nc = true
where ctid in (
  select ri.ctid from privado.respuesta_item ri
  join privado.respuesta r on r.id = ri.respuesta_id join public.grupo g on g.id = r.grupo_id
  join public.pregunta p on p.id = ri.pregunta_id join public.asignatura a on a.id = ri.asignatura_id
  where g.nombre = 'Y7 B' and p.codigo_diccionario = 'prof_claridad' and a.nombre = 'Matemáticas' and ri.valor is not null
  order by r.id limit 3);

create function pg_temp.celda(p_metrica jsonb, p_clave jsonb) returns jsonb language sql as $$
  select x from jsonb_array_elements(public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', p_metrica, '{grupo,asignatura}') -> 'partes') x
  where x -> 'clave' = p_clave $$;

-- 1. La coordinación ------------------------------------------------------------------------------------------------
select pg_temp.como('coord_pai');
select is(pg_temp.celda('{"tipo":"pregunta","codigo":"prof_claridad"}', '{"grupo":"Y7 B","asignatura":"Matemáticas"}') ->> 'motivo',
  'menos_de_5', 'claridad en Y7 B, Matemáticas (4): «menos de 5»');
select is(pg_temp.celda('{"tipo":"bloque","codigo":"profesorado"}', '{"grupo":"Y7 B","asignatura":"Matemáticas"}') ->> 'suprimido',
  'false', 'el bloque en esa clase se ve');
select is(pg_temp.celda('{"tipo":"pregunta","codigo":"prof_trato"}', '{"grupo":"Y7 B","asignatura":"Matemáticas"}') ->> 'motivo',
  'complementaria', 'el trato en esa clase se oculta también: si no, bloque menos trato daría la claridad');
select is((select count(*)::int from pg_temp.deducibles('{"curso":"2000/01","colectivo":"alumnos"}', '{}')), 0, 'nada que restar: sin dimensiones');
select is((select count(*)::int from pg_temp.deducibles('{"curso":"2000/01","colectivo":"alumnos"}', '{grupo}')), 0, '... por grupo');
select is((select count(*)::int from pg_temp.deducibles('{"curso":"2000/01","colectivo":"alumnos"}', '{asignatura}')), 0, '... por asignatura');
select is((select count(*)::int from pg_temp.deducibles('{"curso":"2000/01","colectivo":"alumnos"}', '{grupo,asignatura}')), 0,
  '... por asignatura y grupo');
select ok((select count(*) from ded_celda where tabla like 'Q:%') > 0 and (select count(*) from ded_celda where tabla like 'B:%') > 0
          and (select count(*) from ded_celda where tabla = 'S') > 0, '... después de pedir la satisfacción, los bloques y las preguntas');
create temp table conjunta as select tabla, clave, oculta from ded_celda;

-- El informe del docente (también para la coordinación) sale con las mismas celdas.
select is((select c ->> 'motivo' from jsonb_array_elements(public.detalle_profesor('2000/01',
             (select id from public.persona_responsable where apellidos = 'Uno')) -> 'preguntas') p,
           jsonb_array_elements(p -> 'resultado' -> 'celdas') c
           where p ->> 'codigo' = 'prof_trato' and c -> 'clave' ->> 'grupo' = 'Y7 B'), 'complementaria',
  'en el informe del docente, el trato en Y7 B también está oculto');

-- 2. Dirección no cambia ---------------------------------------------------------------------------------------------
select pg_temp.como('direccion');
select is((pg_temp.celda('{"tipo":"pregunta","codigo":"prof_claridad"}', '{"grupo":"Y7 B","asignatura":"Matemáticas"}') ->> 'n')::int, 4,
  'Dirección ve la claridad en Y7 B con su n (4)');
select is(pg_temp.celda('{"tipo":"pregunta","codigo":"prof_trato"}', '{"grupo":"Y7 B","asignatura":"Matemáticas"}') ->> 'suprimido', 'false',
  '... y el trato');

-- 3. La métrica interna no se puede pedir desde fuera -----------------------------------------------------------------
select pg_temp.como('coord_pai');
set local role authenticated;
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"familia"}', '{grupo}') $$, 'P0001', null,
  'la métrica «familia» es interna');
select throws_ok($$ select privado.celdas_suprimidas('{1}', '{}', '{"tipo":"bloque","codigo":"profesorado"}') $$, '42501', null,
  'la supresión conjunta no se llama desde fuera');
set local role postgres;

-- 4. Con el motor anterior (tabla a tabla) sí se podía restar ---------------------------------------------------------
create or replace function privado.celdas_suprimidas(p_cuest integer[], p_dims text[], p_metrica jsonb)
returns table (k1 text, k2 text, agg1 boolean, agg2 boolean, n integer, datos jsonb, motivo text)
language plpgsql volatile security definer set search_path = '' as $$
declare a_k1 text[]; a_k2 text[]; a_g1 boolean[]; a_g2 boolean[]; a_n integer[]; a_d jsonb[]; v_mot text[];
begin
  select array_agg(x.k1), array_agg(x.k2), array_agg(x.agg1), array_agg(x.agg2), array_agg(x.n), array_agg(x.datos)
    into a_k1, a_k2, a_g1, a_g2, a_n, a_d from privado.celdas(p_cuest, p_dims, p_metrica) x;
  v_mot := privado.suprimir(a_k1, a_k2, a_g1, a_g2, a_n);
  return query select u.* from unnest(a_k1, a_k2, a_g1, a_g2, a_n, a_d, v_mot) u;
end $$;
select is(pg_temp.celda('{"tipo":"pregunta","codigo":"prof_trato"}', '{"grupo":"Y7 B","asignatura":"Matemáticas"}') ->> 'suprimido',
  'false', 'antes: el trato en Y7 B se veía');
select ok((select count(*) from pg_temp.deducibles('{"curso":"2000/01","colectivo":"alumnos"}', '{grupo,asignatura}')
           where tabla = 'B:profesorado' and clave = '{"grupo":"Y7 B","asignatura":"Matemáticas"}') = 1,
  '... y la claridad se despejaba restando el trato del bloque: el test lo detecta');
select ok((select count(*) from ded_celda d join conjunta c using (tabla, clave) where d.oculta and not c.oculta) = 0,
  'lo que ocultaba el motor anterior lo sigue ocultando el nuevo');

select * from finish();
rollback;
