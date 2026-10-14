-- Vista de profesor (§7.2 y §5.3) y permisos por rol (§6).
begin;
\ir fixtures/datos_ejemplo.psql
select plan(27);

create temp table ids as
  select (select id from public.persona_responsable where apellidos = 'Uno') as uno,
         (select id from public.persona_responsable where apellidos = 'Dos') as dos,
         (select avg(i.valor) from privado.respuesta_item i
            join public.asignatura a on a.id = i.asignatura_id
            join privado.respuesta r on r.id = i.respuesta_id
            join public.grupo g on g.id = r.grupo_id
            where a.nombre = 'Matemáticas' and g.nombre = 'Y7 B' and a.curso_id = (select id from public.curso where nombre = '2000/01') and i.valor is not null) as mates_y7b;
grant select on ids to authenticated;

-- Dirección
reset role; select pg_temp.como('direccion'); set local role authenticated;
create temp table prof_uno as select public.resultados_profesor('2000/01', (select uno from ids)) as r;

select is((select jsonb_array_length(r -> 'celdas') from prof_uno), 4, 'Docente Uno tiene cuatro combinaciones (Matemáticas en Y7 A a Y7 D)');
select is((select string_agg(c -> 'clave' ->> 'grupo' || ':' || coalesce(c ->> 'motivo', 'visible'), ', ' order by c -> 'clave' ->> 'grupo')
           from prof_uno, jsonb_array_elements(r -> 'celdas') c),
  'Y7 A:complementaria, Y7 B:visible, Y7 C:menos_de_5, Y7 D:complementaria',
  'cada combinación tiene el mismo estado que en la tabla asignatura por grupo de dirección');
select is((select (r -> 'global' ->> 'media')::numeric from prof_uno), (select mates_y7b from ids),
  'la media global solo usa las combinaciones visibles');
select is((select (r -> 'global' ->> 'combinaciones')::int from prof_uno), 1, 'una combinación visible');
select is((select (r ->> 'combinaciones_excluidas')::int from prof_uno), 3, 'el informe cuenta las combinaciones excluidas');
select ok((select r -> 'comparacion' ? 'pai' and r -> 'comparacion' ? 'colegio' from prof_uno), 'compara con su etapa y con el colegio');
select ok((select not (c ?| array['n', 'media', 'n_valoraciones'])
           from prof_uno, jsonb_array_elements(r -> 'celdas') c where c -> 'clave' ->> 'grupo' = 'Y7 C'),
  'una combinación suprimida no devuelve datos');
select is((public.resultados_profesor('2000/01', (select dos from ids)) -> 'global' ->> 'n_personas_por_asignatura')::int, 8,
  'Docente Dos (Lengua en Y7 B) es visible');
select is((public.resultados_profesor('2000/01', (select uno from ids), '{"tipo":"pregunta","codigo":"prof_trato"}') -> 'global' ->> 'n_valoraciones')::int, 8,
  'la vista de profesor admite el detalle por pregunta');
select is(jsonb_array_length(public.listar_profesores('2000/01')), 2, 'dirección ve todos los profesores');

-- Coordinación de PAI
reset role; select pg_temp.como('coord_pai'); set local role authenticated;
select lives_ok($$ select public.resultados_profesor('2000/01', (select uno from ids)) $$, 'coordinación de PAI ve a un profesor de PAI');
select ok(public.resultados_profesor('2000/01', (select uno from ids)) -> 'comparacion' ? 'colegio',
  'coordinación recibe la media del colegio como referencia');
select is(jsonb_array_length(public.listar_profesores('2000/01')), 2, 'coordinación de PAI ve los profesores de PAI');
select is((public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"personas"}') -> 'total' ->> 'n')::int, 29,
  'coordinación de PAI ve los alumnos de PAI');
select is((public.resultados('{"curso":"2000/01","colectivo":"familias"}', '{"tipo":"personas"}', '{etapa}') -> 'total' -> 'clave' ->> 'etapa'),
  'pai', 'en familias, coordinación solo recibe su etapa aunque pida el reparto');
select is((public.resultados('{"curso":"2000/01","colectivo":"familias"}', '{"tipo":"personas"}', '{etapa}') -> 'partes'),
  '[]'::jsonb, 'y no recibe las demás etapas');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"familias","etapa":"primaria"}', '{"tipo":"personas"}') $$,
  '42501', 'Sin acceso a la etapa primaria', 'coordinación no pide otra etapa en familias');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"alumnos","etapa":"primaria"}', '{"tipo":"personas"}') $$,
  '42501', 'Sin acceso a la etapa primaria', 'coordinación no pide otra etapa en alumnos');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal"}', '{"tipo":"personas"}') $$,
  '42501', 'Sin acceso a los resultados de personal', 'coordinación no ve personal');
select throws_ok($$ select public.recuento_idiomas('2000/01') $$,
  '42501', 'Sin acceso a los resultados de personal', 'coordinación no ve el recuento por idioma de personal');
select throws_ok($$ select public.resumen('{"curso":"2000/01","colectivo":"personal"}') $$,
  '42501', 'Sin acceso a los resultados de personal', 'coordinación no ve personal tampoco en el resumen');

-- Coordinación de Primaria e Infantil
reset role; select pg_temp.como('coord_primaria'); set local role authenticated;
select throws_ok($$ select public.resultados_profesor('2000/01', (select uno from ids)) $$,
  '42501', 'Sin acceso a este profesor', 'coordinación de Primaria no ve a un profesor que solo da clase en PAI');
select is(public.listar_profesores('2000/01'), '[]'::jsonb, 'coordinación de Primaria no ve profesores de otras etapas');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"personas"}') $$,
  'P0002', 'No hay datos para este filtro', 'coordinación de Primaria no ve alumnos de PAI');
select is((public.resultados('{"curso":"2000/01","colectivo":"familias"}', '{"tipo":"personas"}') -> 'total' ->> 'n')::int, 11,
  'coordinación de Primaria ve las familias de Primaria (incluida la que también tiene hijos en PAI)');
reset role; select pg_temp.como('coord_infantil'); set local role authenticated;
select is((public.resultados('{"curso":"2000/01","colectivo":"familias"}', '{"tipo":"personas"}') -> 'total' ->> 'motivo'), 'complementaria',
  'coordinación de Infantil recibe su etapa suprimida igual que la ve dirección');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"personas"}') $$,
  'P0002', 'No hay datos para este filtro', 'coordinación de Infantil no tiene encuesta de alumnos');

select * from finish();
rollback;
