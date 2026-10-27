-- Identificador aleatorio en las respuestas y referencia del colegio para la coordinación en Familias
-- (decisiones del 26/10/2026).
begin;
\ir fixtures/datos_ejemplo.psql
select plan(12);

-- Identificador aleatorio -------------------------------------------------------------------------------------
select is((select is_identity from information_schema.columns where table_schema = 'privado' and table_name = 'respuesta' and column_name = 'id'),
          'NO', 'el identificador de la respuesta ya no es correlativo');
select is((select column_default from information_schema.columns where table_schema = 'privado' and table_name = 'respuesta' and column_name = 'id'),
          'privado.id_aleatorio()', 'se toma al azar');
select is((select column_default from information_schema.columns where table_schema = 'privado' and table_name = 'respuesta_item' and column_name = 'id'),
          'privado.id_aleatorio()', 'también el de cada valoración');
select is((select count(*)::int from (select id - lag(id) over (order by id) as salto from privado.respuesta) x where salto = 1), 0,
          'ninguna respuesta tiene el identificador siguiente al de otra');

-- Referencia del colegio ------------------------------------------------------------------------------------------
set local role postgres; select pg_temp.como('direccion'); set local role authenticated;
create temp table total_familias as
  select (public.resultados('{"curso":"2000/01","colectivo":"familias"}', '{"tipo":"personas"}') -> 'total' ->> 'n')::int as n,
         public.resultados('{"curso":"2000/01","colectivo":"familias"}', '{"tipo":"bloque","codigo":"centro"}') -> 'total' ->> 'media' as media;
select is((public.resultados('{"curso":"2000/01","colectivo":"familias","referencia":true}', '{"tipo":"personas"}') -> 'total' ->> 'n')::int,
          (select n from total_familias), 'la referencia es el total de familias del colegio');
grant select on total_familias to authenticated;

set local role postgres; select pg_temp.como('coord_primaria'); set local role authenticated;
select is((public.resultados('{"curso":"2000/01","colectivo":"familias","referencia":true}', '{"tipo":"personas"}') -> 'total' ->> 'n')::int,
          (select n from total_familias), 'la coordinación ve el total de familias del colegio como referencia');
select is(public.resultados('{"curso":"2000/01","colectivo":"familias","referencia":true}', '{"tipo":"bloque","codigo":"centro"}') -> 'total' ->> 'media',
          (select media from total_familias), 'también la media de cada bloque');
select ok((public.resultados('{"curso":"2000/01","colectivo":"familias"}', '{"tipo":"personas"}') -> 'total' ->> 'n')::int
          is distinct from (select n from total_familias), 'sin la referencia, sigue viendo solo su etapa');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"familias","referencia":true}', '{"tipo":"personas"}', '{etapa}') $$,
  'P0001', 'La referencia del Colegio es solo el total de familias, sin filtros ni repartos', 'la referencia no se reparte por etapa');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"familias","referencia":true,"etapa":"pai"}', '{"tipo":"personas"}') $$,
  'P0001', 'La referencia del Colegio es solo el total de familias, sin filtros ni repartos', 'ni sirve para pedir otra etapa');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"alumnos","referencia":true}', '{"tipo":"personas"}') $$,
  'P0001', 'La referencia del Colegio es solo el total de familias, sin filtros ni repartos', 'solo existe en familias');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"familias","etapa":"pai"}', '{"tipo":"personas"}') $$,
  '42501', 'Sin acceso a la etapa pai', 'fuera de la referencia, otra etapa sigue prohibida');

select * from finish();
rollback;
