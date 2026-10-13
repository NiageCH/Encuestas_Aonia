-- Cálculos (§3): media agrupada, NS/NC, NPS, significado de n y "lo más valorado".
-- Los valores esperados salen de SQL independiente sobre las tablas en bruto (como
-- postgres) o de cifras calculadas a mano a partir de la fixture.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(18);

create temp table esperado as
with prof as (
  select r.id as resp, i.valor
  from privado.respuesta_item i
  join privado.respuesta r on r.id = i.respuesta_id
  join public.pregunta p on p.id = i.pregunta_id
  where p.codigo_diccionario in ('prof_claridad', 'prof_trato') and i.valor is not null
)
select
  (select avg(valor) from prof) as prof_agrupada,
  (select avg(m) from (select avg(valor) m from prof group by resp) t) as prof_por_persona,
  (select count(*) from privado.respuesta_item i join public.pregunta p on p.id = i.pregunta_id
     where p.codigo_diccionario in ('prof_claridad', 'prof_trato') and i.ns_nc) as prof_ns_nc,
  (select avg(i.valor) from privado.respuesta_item i
     join public.pregunta p on p.id = i.pregunta_id
     join privado.respuesta r on r.id = i.respuesta_id
     join public.cuestionario c on c.id = r.cuestionario_id
     where c.codigo = 'PAI_T' and p.codigo_diccionario in ('prof_claridad', 'prof_trato', 'centro_ambiente', 'sat_general')
       and i.valor is not null) as satisfaccion_pai,
  (select avg(i.valor) from privado.respuesta_item i
     join public.asignatura a on a.id = i.asignatura_id
     join privado.respuesta r on r.id = i.respuesta_id
     join public.grupo g on g.id = r.grupo_id
     where a.nombre = 'Matemáticas' and g.nombre = 'Y7 B' and i.valor is not null) as mates_y7b,
  (select avg(i.valor) from privado.respuesta_item i join public.pregunta p on p.id = i.pregunta_id
     where p.codigo_diccionario = 'rec_familias') as rec_familias_media;

grant select on esperado to authenticated;

reset role; select pg_temp.como('direccion'); set local role authenticated;

-- Media agrupada, no media de medias por persona
select ok((select prof_agrupada <> prof_por_persona from esperado), 'la fixture distingue media agrupada y media por persona');
select is((public.resultados('{"curso":"2025/26","colectivo":"alumnos"}', '{"tipo":"bloque","codigo":"profesorado"}') -> 'total' ->> 'media')::numeric,
  (select prof_agrupada from esperado), 'la media de un bloque es la media agrupada de todas sus valoraciones');
select is((public.resultados('{"curso":"2025/26","colectivo":"alumnos"}', '{"tipo":"bloque","codigo":"profesorado"}') -> 'total' ->> 'ns_nc')::int,
  (select prof_ns_nc::int from esperado), 'NS/NC se cuenta aparte');
select is((public.resultados('{"curso":"2025/26","colectivo":"alumnos"}', '{"tipo":"bloque","codigo":"profesorado"}') -> 'total' ->> 'n_valoraciones')::int,
  54 + 42, 'NS/NC no cuenta en las valoraciones válidas (54 de Matemáticas y 42 de Lengua)');

-- Satisfacción media: excluye recomendación, selección múltiple y la escala de 1 a 4
select is((public.resultados('{"curso":"2025/26","colectivo":"alumnos"}', '{"tipo":"satisfaccion"}') -> 'total' ->> 'media')::numeric,
  (select satisfaccion_pai from esperado), 'la satisfacción media solo incluye preguntas de 1 a 6 en bloques que entran en media');

-- n: personas en una asignatura o grupo, valoraciones en una pregunta
select is((public.resultados('{"curso":"2025/26","colectivo":"alumnos","asignatura":"Lengua"}', '{"tipo":"bloque","codigo":"profesorado"}') -> 'total' ->> 'n')::int,
  21, 'n de una asignatura = personas con al menos una valoración válida (4 + 8 + 3 + 6)');
select is((public.resultados('{"curso":"2025/26","colectivo":"alumnos","asignatura":"Matemáticas"}', '{"tipo":"pregunta","codigo":"prof_claridad"}') -> 'total' ->> 'n')::int,
  25, 'n de una pregunta = valoraciones válidas (29 menos 4 NS/NC)');
select is((public.resultados('{"curso":"2025/26","colectivo":"alumnos","grupo":"Y7 B","asignatura":"Matemáticas"}', '{"tipo":"bloque","codigo":"profesorado"}') -> 'total' ->> 'media')::numeric,
  (select mates_y7b from esperado), 'media de una combinación asignatura y grupo');

-- Distribución
select is((public.resultados('{"curso":"2025/26","colectivo":"alumnos"}', '{"tipo":"pregunta","codigo":"sat_general"}') -> 'total' -> 'distribucion'),
  '{"1": 4, "2": 4, "3": 6, "4": 6, "5": 5, "6": 4}'::jsonb, 'la distribución cuenta cada valor de la escala');

-- Recomendación y NPS en escala de 1 a 10 (personal): 10 dieces, 4 nueves, 5 sietes y 5 treses
create temp table rec_personal as
  select public.resultados('{"curso":"2025/26","colectivo":"personal"}', '{"tipo":"recomendacion"}') -> 'total' as t;
select is((select (t ->> 'media')::numeric from rec_personal), 7.75, 'recomendación media de personal');
select is((select (t ->> 'nps')::numeric from rec_personal), 37.5, 'NPS = % de 9 y 10 menos % de 6 o menos');
select is((select round((t ->> 'promotores_pct')::numeric + (t ->> 'neutros_pct')::numeric + (t ->> 'detractores_pct')::numeric, 10) from rec_personal),
  100::numeric, 'promotores, neutros y detractores suman 100');
select ok(scale((public.resultados('{"curso":"2025/26","colectivo":"alumnos"}', '{"tipo":"bloque","codigo":"profesorado"}') -> 'total' ->> 'media')::numeric) > 2,
  'las RPC devuelven las medias sin redondear');

-- NPS en escala de 0 a 10 (alumnos): valores s % 11 por alumno
select is(round((public.resultados('{"curso":"2025/26","colectivo":"alumnos"}', '{"tipo":"recomendacion"}') -> 'total' ->> 'nps')::numeric, 10),
  round(100.0 * (2 - 23) / 29, 10), 'NPS en escala de 0 a 10 con el mismo umbral (2 promotores, 23 detractores)');
select is((public.resultados('{"curso":"2025/26","colectivo":"familias"}', '{"tipo":"recomendacion"}') -> 'total' ->> 'media')::numeric,
  (select rec_familias_media from esperado), 'recomendación media de familias (escala de 1 a 10)');

-- Lo más valorado: porcentaje sobre quienes contestan la pregunta
create temp table valorado as
  select public.resultados('{"curso":"2025/26","colectivo":"alumnos"}', '{"tipo":"seleccion","codigo":"mas_valorado"}') -> 'total' as t;
select is((select (t ->> 'n')::int from valorado), 25, 'n de lo más valorado = personas que contestan la pregunta (29 menos 4)');
select is((select (o ->> 'n')::int from valorado, jsonb_array_elements(t -> 'opciones') o where o ->> 'codigo' = 'profesorado'),
  13, 'personas que eligen Profesorado');
select is((select (o ->> 'pct')::numeric from valorado, jsonb_array_elements(t -> 'opciones') o where o ->> 'codigo' = 'profesorado'),
  52::numeric, 'porcentaje de Profesorado (13 de 25)');

select * from finish();
rollback;
