-- Panel de Inicio: puntos fuertes y de mejora por colectivo, y «En qué se diferencian quienes no
-- recomendarían el Colegio» (dimensión «recomienda», aislada de cualquier otro filtro).
begin;
\ir fixtures/datos_ejemplo.psql
select plan(22);
-- Estos tests comprueban el mínimo de 5 y la complementaria, que siguen valiendo para la coordinación y para la versión
-- docente del informe. Dirección y administración las ven aquí como en esa versión; su criterio está en 25_criterio_direccion.sql.
set local encuestas.version_docente = 'on';

-- Una pregunta de personal con solo 3 valoraciones: nunca debe salir en los puntos.
do $$
declare
  v_per integer := (select id from public.cuestionario where codigo = 'PER_T');
  b integer := (select id from public.bloque where cuestionario_id = v_per and codigo = 'centro');
  q integer;
begin
  insert into public.pregunta (codigo_diccionario, texto_es, tipo, escala_min, escala_max)
    values ('per_pocas', 'Pregunta con pocas respuestas', 'escala', 1, 6) returning id into q;
  insert into public.pregunta_cuestionario (cuestionario_id, pregunta_id, bloque_id, orden) values (v_per, q, b, 9);
  insert into privado.respuesta_item (respuesta_id, pregunta_id, valor, ns_nc)
    select id, q, 1, false from privado.respuesta where cuestionario_id = v_per order by id limit 3;
end $$;

create temp table esperado as
  select (select avg(i.valor) from privado.respuesta_item i join public.pregunta p on p.id = i.pregunta_id
           join privado.respuesta r on r.id = i.respuesta_id join public.cuestionario c on c.id = r.cuestionario_id
          where c.codigo = 'PER_T' and p.codigo_diccionario = 'sup_trato'
            and exists (select 1 from privado.respuesta_item ri join public.pregunta rp on rp.id = ri.pregunta_id
                        where ri.respuesta_id = r.id and rp.tipo = 'recomendacion' and ri.valor >= 9)) as sup_si,
         (select avg(i.valor) from privado.respuesta_item i join public.pregunta p on p.id = i.pregunta_id
           join privado.respuesta r on r.id = i.respuesta_id join public.cuestionario c on c.id = r.cuestionario_id
          where c.codigo = 'PER_T' and p.codigo_diccionario = 'sup_trato'
            and exists (select 1 from privado.respuesta_item ri join public.pregunta rp on rp.id = ri.pregunta_id
                        where ri.respuesta_id = r.id and rp.tipo = 'recomendacion' and ri.valor <= 6)) as sup_no;
grant select on esperado to authenticated;

set local role postgres; select pg_temp.como('direccion'); set local role authenticated;

-- Puntos fuertes y de mejora ------------------------------------------------------------------
select ok(jsonb_array_length(public.puntos_colectivo('{"curso":"2000/01","colectivo":"alumnos"}') -> 'mejora') between 1 and 5,
  'puntos de mejora: como mucho 5');
select ok(jsonb_array_length(public.puntos_colectivo('{"curso":"2000/01","colectivo":"alumnos"}') -> 'fuertes') between 1 and 5,
  'puntos fuertes: como mucho 5');
select is((select count(*)::int from jsonb_array_elements(public.puntos_colectivo('{"curso":"2000/01","colectivo":"alumnos"}') -> 'mejora') e
           where e ->> 'codigo' = 'ib_autoeval'), 0, 'solo preguntas de 1 a 6 (la autoevaluación de 1 a 4 no entra)');
select is((select count(*)::int from jsonb_array_elements(public.puntos_colectivo('{"curso":"2000/01","colectivo":"personal"}', 50) -> 'mejora') e
           where e ->> 'codigo' = 'per_pocas'), 0, 'una pregunta con menos de 5 valoraciones nunca sale');
select is((select count(*)::int from jsonb_array_elements(public.puntos_colectivo('{"curso":"2000/01","colectivo":"personal"}', 50) -> 'mejora') e
           where e ->> 'codigo' = 'dep_utiles'), 0, 'las reuniones de departamento (aisladas) no entran');
select ok((select bool_and((e ->> 'n')::int >= 5) from jsonb_array_elements(public.puntos_colectivo('{"curso":"2000/01","colectivo":"alumnos"}', 50) -> 'mejora') e),
  'todas las preguntas mostradas tienen 5 o más valoraciones');
select ok((select (public.puntos_colectivo('{"curso":"2000/01","colectivo":"alumnos"}') -> 'mejora' -> 0 ->> 'media')::numeric
               <= (public.puntos_colectivo('{"curso":"2000/01","colectivo":"alumnos"}') -> 'fuertes' -> 0 ->> 'media')::numeric),
  'la peor de mejora no supera a la mejor de fuertes');
select ok((select bool_and((e ->> 'pct_bajo')::numeric between 0 and 100) from jsonb_array_elements(public.puntos_colectivo('{"curso":"2000/01","colectivo":"familias"}') -> 'fuertes') e),
  'cada punto lleva el porcentaje que da de 1 a 3');
select throws_ok($$ select public.puntos_colectivo('{"curso":"2000/01","colectivo":"alumnos","grupo":"Y7 A"}') $$,
  'P0001', 'Los puntos fuertes y de mejora son del total del colectivo, sin filtros', 'sin filtros de grupo');

-- En qué se diferencian quienes no recomendarían el Colegio -----------------------------------
select is((select (x -> 'no_recomienda' ->> 'n')::int from jsonb_array_elements(public.comparacion_recomendacion('2000/01', 'personal')) x
           where x ->> 'bloque' = 'superiores'), 5, 'personal: 5 personas no lo recomendarían (de 0 a 6)');
select is((select (x -> 'recomienda' ->> 'n')::int from jsonb_array_elements(public.comparacion_recomendacion('2000/01', 'personal')) x
           where x ->> 'bloque' = 'superiores'), 14, 'y 14 sí (9 y 10)');
select is((select (x ->> 'diferencia')::numeric from jsonb_array_elements(public.comparacion_recomendacion('2000/01', 'personal')) x
           where x ->> 'bloque' = 'superiores'), (select sup_si - sup_no from esperado), 'la diferencia es la de las dos medias');
select is((select count(*)::int from jsonb_array_elements(public.comparacion_recomendacion('2000/01', 'personal')) x
           where x ->> 'bloque' = 'reuniones_departamento'), 0, 'las reuniones de departamento no se comparan');
select ok((select bool_and(case when (p ->> 'suprimido')::boolean then true else (p ->> 'n')::int >= 5 end)
           from jsonb_array_elements(public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"bloque","codigo":"centro"}', '{recomienda}') -> 'partes') p),
  'ningún grupo visible con menos de 5');
select isnt((select count(*)::int from jsonb_array_elements(public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"bloque","codigo":"centro"}', '{recomienda}') -> 'partes') p
             where (p ->> 'suprimido')::boolean), 1, 'nunca queda un solo grupo oculto (supresión complementaria)');

-- La dimensión «recomienda» no se cruza con nada
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"alumnos","grupo":"Y7 A"}', '{"tipo":"bloque","codigo":"centro"}', '{recomienda}') $$,
  'P0001', 'La comparación por recomendación no se combina con otros filtros', 'no se combina con el grupo');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal","docente":true}', '{"tipo":"bloque","codigo":"superiores"}', '{recomienda}') $$,
  'P0001', 'La comparación por recomendación no se combina con otros filtros', 'ni con un segmento de personal');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"familias"}', '{"tipo":"personas"}', '{recomienda}') $$,
  'P0001', 'La comparación por recomendación solo vale para la media de un bloque, sin otros filtros', 'no se cuentan personas por recomendación');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"familias"}', '{"tipo":"pregunta","codigo":"centro_ambiente"}', '{recomienda}') $$,
  'P0001', 'La comparación por recomendación solo vale para la media de un bloque, sin otros filtros', 'ni pregunta a pregunta');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"familias"}', '{"tipo":"seleccion","codigo":"test_mas_valorado"}', '{recomienda}') $$,
  'P0001', null, 'ni lo más valorado');

-- Coordinación
set local role postgres; select pg_temp.como('coord_pai'); set local role authenticated;
select throws_ok($$ select public.comparacion_recomendacion('2000/01', 'alumnos') $$,
  '42501', 'Sin acceso a la comparación por recomendación', 'coordinación: sin la comparación por recomendación');
select throws_ok($$ select public.puntos_colectivo('{"curso":"2000/01","colectivo":"personal"}') $$,
  '42501', 'Sin acceso a los resultados de personal', 'coordinación: sin puntos de personal');

select * from finish();
rollback;
