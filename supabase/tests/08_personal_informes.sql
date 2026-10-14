-- Personal → Informes por persona (§7.0 y §6): lo que puede pedir cada rol al servidor en la
-- nueva navegación. La coordinación solo llega a Profesores (los de su etapa); la encuesta de
-- personal y los niveles Dirección, Equipos y Departamentos son de administración y dirección.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(20);

create temp table ids as
  select (select id from public.persona_responsable where apellidos = 'Uno') as uno,
         (select avg(i.valor) from privado.respuesta_item i
            join public.asignatura a on a.id = i.asignatura_id
            join privado.respuesta r on r.id = i.respuesta_id
            join public.grupo g on g.id = r.grupo_id
            where a.nombre = 'Matemáticas' and g.nombre = 'Y7 B' and a.curso_id = (select id from public.curso where nombre = '2000/01')
              and i.valor is not null) as mates_y7b;
grant select on ids to authenticated;

-- Dirección ve todos los niveles
reset role; select pg_temp.como('direccion'); set local role authenticated;
select lives_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal"}', '{"tipo":"personas"}') $$, 'dirección: encuesta de personal');
select lives_ok($$ select public.informe_responsable('2000/01', 'superiores') $$, 'dirección: nivel Dirección (Superiores)');
select is((public.informe_responsable('2000/01', 'centro') -> 'total' ->> 'n')::int, 24, 'dirección: nivel Dirección (valoración del centro por el personal)');
select lives_ok($$ select public.informe_responsable('2000/01', 'equipo_individualizacion') $$, 'dirección: nivel Equipos');
select lives_ok($$ select public.informe_responsable('2000/01', 'departamento', 'Ciencias') $$, 'dirección: nivel Departamentos (reuniones)');
select lives_ok($$ select public.listar_profesores('2000/01') $$, 'dirección: nivel Profesores');

-- Media de los profesores de un departamento según los alumnos: solo combinaciones visibles
select is((public.media_departamento_alumnos('2000/01', 'Ciencias') -> 'global' ->> 'media')::numeric, (select mates_y7b from ids),
  'la media del departamento solo usa las combinaciones asignatura y grupo visibles');
select is((public.media_departamento_alumnos('2000/01', 'Ciencias') ->> 'combinaciones_excluidas')::int, 3,
  'y cuenta las que quedan fuera');
select is((public.media_departamento_alumnos('2000/01', 'Ciencias') ->> 'profesores')::int, 1, 'profesores del departamento');
select is((public.media_departamento_alumnos('2000/01', 'Letras') -> 'global' ->> 'motivo'), 'sin_asignacion',
  'un departamento sin profesores asignados no tiene media de alumnos');

-- Coordinación: solo Profesores de su etapa
reset role; select pg_temp.como('coord_pai'); set local role authenticated;
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal"}', '{"tipo":"personas"}') $$,
  '42501', 'Sin acceso a los resultados de personal', 'coordinación: no ve la encuesta de personal');
select throws_ok($$ select public.informe_responsable('2000/01', 'superiores') $$,
  '42501', 'Sin acceso a los informes de responsables', 'coordinación: no ve Dirección (Superiores)');
select throws_ok($$ select public.informe_responsable('2000/01', 'centro') $$,
  '42501', 'Sin acceso a los informes de responsables', 'coordinación: no ve Dirección (valoración del centro)');
select throws_ok($$ select public.informe_responsable('2000/01', 'equipo_individualizacion') $$,
  '42501', 'Sin acceso a los informes de responsables', 'coordinación: no ve Equipos');
select throws_ok($$ select public.informe_responsable('2000/01', 'departamento', 'Ciencias') $$,
  '42501', 'Sin acceso a los informes de responsables', 'coordinación: no ve Departamentos (reuniones)');
select throws_ok($$ select public.media_departamento_alumnos('2000/01', 'Ciencias') $$,
  '42501', 'Sin acceso a los informes de responsables', 'coordinación: no ve Departamentos (media de alumnos)');
select is(jsonb_array_length(public.listar_profesores('2000/01')), 2, 'coordinación de PAI: ve los profesores de su etapa');
select lives_ok($$ select public.informe_profesor('2000/01', (select uno from ids)) $$, 'coordinación de PAI: informe de un profesor de su etapa');

reset role; select pg_temp.como('coord_primaria'); set local role authenticated;
select is(public.listar_profesores('2000/01'), '[]'::jsonb, 'coordinación de Primaria: no ve profesores de otras etapas');
select throws_ok($$ select public.informe_profesor('2000/01', (select uno from ids)) $$,
  '42501', 'Sin acceso a este profesor', 'coordinación de Primaria: ni su informe');

select * from finish();
rollback;
