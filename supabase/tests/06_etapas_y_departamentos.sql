-- Familias con varias etapas, bloque de reuniones de departamento aislado, alumnos sin
-- grupo y n de personas (solo quien tiene alguna respuesta válida).
begin;
\ir fixtures/datos_ejemplo.psql
select plan(21);

create function pg_temp.parte(p jsonb, p_clave jsonb) returns jsonb
language sql as $$ select e from jsonb_array_elements(p -> 'partes') e where e -> 'clave' = p_clave $$;
grant execute on function pg_temp.parte(jsonb, jsonb) to authenticated;

create temp table esperado as select
  (select avg(i.valor) from privado.respuesta_item i
     join privado.respuesta r on r.id = i.respuesta_id
     join public.cuestionario c on c.id = r.cuestionario_id
     join public.pregunta p on p.id = i.pregunta_id
     where c.codigo = 'PER_T' and p.codigo_diccionario in ('sup_trato', 'centro_ambiente') and i.valor is not null) as satisfaccion_personal,
  (select avg(i.valor) from privado.respuesta_item i
     join public.departamento d on d.id = i.departamento_id
     where d.nombre = 'Ciencias' and d.curso_id = (select id from public.curso where nombre = '2000/01') and i.valor is not null) as dep_ciencias;
grant select on esperado to authenticated;

reset role; select pg_temp.como('direccion'); set local role authenticated;

-- Familias: una familia con hijos en Primaria y PAI cuenta en las dos etapas y una vez en el total
create temp table r_etapas as
  select public.resultados('{"curso":"2000/01","colectivo":"familias"}', '{"tipo":"personas"}', '{etapa}') as r;
select is((select (r -> 'total' ->> 'n')::int from r_etapas), 29, 'en el total cada familia cuenta una vez');
select is((select (pg_temp.parte(r, '{"etapa":"primaria"}') ->> 'n')::int from r_etapas), 11, 'la familia cuenta en Primaria');
select is((select (pg_temp.parte(r, '{"etapa":"pai"}') ->> 'n')::int from r_etapas), 10, 'y también en PAI');
select ok((select sum((e ->> 'n')::int) from r_etapas, jsonb_array_elements(r -> 'partes') e where not (e ->> 'suprimido')::boolean)
          > (select (r -> 'total' ->> 'n')::int - 9 from r_etapas),
  'las etapas se solapan: sus partes no suman el total');
select is((select pg_temp.parte(r, '{"etapa":"bachillerato"}') ->> 'motivo' from r_etapas), 'menos_de_5',
  'Bachillerato (3) sigue suprimido');
select is((select pg_temp.parte(r, '{"etapa":"infantil"}') ->> 'motivo' from r_etapas), 'complementaria',
  'la supresión complementaria se aplica igual entre etapas solapadas');
select is((public.resultados('{"curso":"2000/01","colectivo":"familias","etapa":"primaria"}', '{"tipo":"pregunta","codigo":"centro_ambiente"}') -> 'total' ->> 'n')::int,
  11, 'pedir una etapa directamente cuenta la familia de dos etapas');
select is((public.resultados('{"curso":"2000/01","colectivo":"familias"}', '{"tipo":"pregunta","codigo":"centro_ambiente"}') -> 'total' ->> 'n_valoraciones')::int,
  29, 'en el total, las valoraciones de la familia de dos etapas no se duplican');

-- Reuniones de departamento: solo por departamento, con el mínimo de 5
create temp table r_dep as
  select public.resultados('{"curso":"2000/01","colectivo":"personal"}', '{"tipo":"bloque","codigo":"reuniones_departamento"}', '{departamento}') as r;
select is((select (pg_temp.parte(r, '{"departamento":"Ciencias"}') ->> 'media')::numeric from r_dep), (select dep_ciencias from esperado),
  'media de las reuniones de un departamento visible');
select is((select pg_temp.parte(r, '{"departamento":"Artes"}') ->> 'motivo' from r_dep), 'menos_de_5', 'un departamento con 2 personas se suprime');
select is((select pg_temp.parte(r, '{"departamento":"Letras"}') ->> 'motivo' from r_dep), 'complementaria',
  'y el siguiente más pequeño, por complementaria');
select ok(jsonb_array_length(public.detalle_preguntas('{"curso":"2000/01","colectivo":"personal"}', 'reuniones_departamento', '{departamento}')) = 1,
  'el detalle por pregunta del bloque funciona repartido por departamento');

-- Ninguna RPC cruza el bloque con otras respuestas de la misma persona
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal"}', '{"tipo":"bloque","codigo":"reuniones_departamento"}') $$,
  'P0001', 'Las reuniones de departamento solo se consultan repartidas por departamento, sin otros filtros',
  'el bloque no se consulta sin repartir por departamento');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal","docente":true}', '{"tipo":"bloque","codigo":"reuniones_departamento"}', '{departamento}') $$,
  'P0001', 'Las reuniones de departamento solo se consultan repartidas por departamento, sin otros filtros',
  'el bloque no se cruza con docente o no docente');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal","antiguedad":"primer_ano"}', '{"tipo":"pregunta","codigo":"dep_utiles"}', '{departamento}') $$,
  'P0001', 'Las reuniones de departamento solo se consultan repartidas por departamento, sin otros filtros',
  'una pregunta del bloque no se cruza con la antigüedad');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal","departamento":"Ciencias"}', '{"tipo":"bloque","codigo":"superiores"}') $$,
  'P0001', 'La dimensión departamento solo vale para las reuniones de departamento',
  'el departamento del bloque no sirve para filtrar otro bloque (Superiores)');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal"}', '{"tipo":"personas"}', '{departamento}') $$,
  'P0001', 'La dimensión departamento solo vale para las reuniones de departamento',
  'no se cuentan personas por departamento');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal"}', '{"tipo":"seleccion","codigo":"test_mas_valorado"}', '{departamento}') $$,
  'P0001', null, 'ni se reparte lo más valorado por departamento');
select is((public.resultados('{"curso":"2000/01","colectivo":"personal"}', '{"tipo":"satisfaccion"}') -> 'total' ->> 'media')::numeric,
  (select satisfaccion_personal from esperado), 'la satisfacción media de personal no incluye el bloque de departamento');

-- n de personas y alumnos sin grupo
reset role;
insert into privado.respuesta (cuestionario_id, grupo_id)
  select id, null from public.cuestionario where codigo = 'PAI_T';
insert into privado.respuesta_item (respuesta_id, pregunta_id, valor, ns_nc)
  select max(r.id), (select id from public.pregunta where codigo_diccionario = 'sat_general'), null, true
  from privado.respuesta r join public.cuestionario c on c.id = r.cuestionario_id where c.codigo = 'PAI_T';
insert into privado.respuesta (cuestionario_id, grupo_id)
  select id, null from public.cuestionario where codigo = 'PAI_T';
insert into privado.respuesta_item (respuesta_id, pregunta_id, valor, ns_nc)
  select max(r.id), (select id from public.pregunta where codigo_diccionario = 'sat_general'), 4, false
  from privado.respuesta r join public.cuestionario c on c.id = r.cuestionario_id where c.codigo = 'PAI_T';
select pg_temp.como('direccion'); set local role authenticated;

create temp table r_sin_grupo as
  select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"personas"}', '{grupo}') as r;
select is((select (r -> 'total' ->> 'n')::int from r_sin_grupo), 30,
  'n cuenta a quien tiene alguna valoración válida (el alumno sin grupo) y no a quien solo contestó NS/NC');
select is((select pg_temp.parte(r, '{"grupo":"(sin dato)"}') ->> 'motivo' from r_sin_grupo), 'menos_de_5',
  'los alumnos sin grupo nunca se muestran como grupo propio');

select * from finish();
rollback;
