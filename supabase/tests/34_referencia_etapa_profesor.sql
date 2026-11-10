-- Informe del profesor/a (petición de Mark del 10/11/2026): la media de todo el profesorado de una etapa sale también
-- cuando todas las clases del docente en esa etapa quedan ocultas. Es una referencia de toda la etapa: no depende del
-- docente, y fuera de la versión completa sigue saliendo solo la media.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(6);

-- Cuatro da Matemáticas solo en Y7 C (3 alumnos): en la versión docente su única clase queda oculta.
insert into public.persona_responsable (nombre, apellidos, correo) values ('Docente', 'Cuatro', 'docente.cuatro@ejemplo.test');
insert into public.asignacion_docente (curso_id, grupo_id, asignatura_id, docente_id)
  select g.curso_id, g.id, a.id, (select id from public.persona_responsable where apellidos = 'Cuatro')
  from public.grupo g join public.curso cu on cu.id = g.curso_id join public.asignatura a on a.curso_id = cu.id and a.nombre = 'Matemáticas'
  where cu.nombre = '2000/01' and g.nombre = 'Y7 C';
create temp table ids as select (select id from public.persona_responsable where apellidos = 'Cuatro') as cuatro,
                                (select id from public.persona_responsable where apellidos = 'Uno') as uno;
grant select on ids to authenticated;

select pg_temp.como('coord_pai'); set local role authenticated;
create temp table coord as select public.detalle_profesor('2000/01', (select cuatro from ids)) as r,
                                  public.detalle_profesor('2000/01', (select uno from ids)) as ref;

select is((select r -> 'global' ->> 'motivo' from coord), 'sin_combinaciones_visibles',
  'versión docente: la única clase de Cuatro está oculta y no tiene media');
select ok((select r -> 'comparacion' ? 'pai' from coord), '... pero sí la media de todo el profesorado de PAI');
select is((select (r -> 'comparacion' -> 'pai' ->> 'media')::numeric from coord), (select (ref -> 'comparacion' -> 'pai' ->> 'media')::numeric from coord),
  '... la misma que en el informe de cualquier otro docente de PAI');
select ok((select bool_and(p -> 'resultado' -> 'comparacion' ? 'pai') from coord, jsonb_array_elements(r -> 'preguntas') p),
  'también en cada pregunta');
select ok((select bool_and(k in ('clave', 'media', 'motivo', 'suprimido')) from coord, jsonb_object_keys(r -> 'comparacion' -> 'pai') k),
  '... solo con la media (sin número de respuestas)');

set local role postgres;
select pg_temp.como('direccion'); set local role authenticated;
select ok((select public.detalle_profesor('2000/01', (select cuatro from ids)) -> 'comparacion' -> 'pai' ? 'n'),
  'Dirección: la comparación completa, como antes');

select * from finish();
rollback;
