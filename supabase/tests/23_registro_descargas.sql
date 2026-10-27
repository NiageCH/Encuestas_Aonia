-- Registro de descargas: cada PDF, CSV o ZIP queda anotado con un código único (uno por informe en un ZIP), con permisos
-- por rol; solo administración lo consulta; nadie lo cambia ni lo borra; la actividad lo deja fuera.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(34);

set local role postgres;
create temp table cod (nombre text primary key, valor text);
grant all on cod to authenticated;
-- Lectura directa del registro (como postgres), para comprobar qué se ha anotado.
create function pg_temp.ultima() returns jsonb language sql security definer as $$
  select detalle from public.registro_actividad where accion = 'descarga' order by id desc limit 1 $$;
grant execute on function pg_temp.ultima() to authenticated;

-- Quién puede anotar qué ----------------------------------------------------------------------------------------------
set local role anon;
select throws_ok($$ select public.registrar_descarga('csv', '{"objeto": "Alumnado", "vista": "alumnos", "archivo": "a.csv"}') $$,
  '42501', null, 'anon no puede descargar');
set local role postgres; select pg_temp.como('admin', 'aal1'); set local role authenticated;
select throws_ok($$ select public.registrar_descarga('csv', '{"objeto": "Alumnado", "vista": "alumnos", "archivo": "a.csv"}') $$,
  '42501', 'Doble factor obligatorio para las cuentas de administración', 'administración, solo con el doble factor');
set local role postgres; select pg_temp.como('inactivo'); set local role authenticated;
select throws_ok($$ select public.registrar_descarga('csv', '{"objeto": "Alumnado", "vista": "alumnos", "archivo": "a.csv"}') $$,
  '42501', 'Sin acceso', 'una cuenta desactivada tampoco');

set local role postgres; select pg_temp.como('coord_pai'); set local role authenticated;
select throws_ok($$ select public.registrar_descarga('informe_jefatura', '{"objeto": "Docente Uno", "persona": 1, "archivo": "j.pdf"}') $$,
  '42501', 'Sin acceso a los informes de responsables', 'la coordinación no descarga informes de jefatura');
select throws_ok($$ select public.registrar_descarga('informe_direccion', '{"objeto": "Dirección", "archivo": "d.pdf"}') $$,
  '42501', 'Sin acceso a los informes de responsables', 'ni de dirección');
select throws_ok($$ select public.registrar_descarga('vista_pdf', '{"objeto": "Personal", "vista": "personal", "archivo": "p.pdf"}') $$,
  '42501', 'Sin acceso a los resultados de personal', 'ni la vista de personal');
select lives_ok($$ insert into cod values ('coord', public.registrar_descarga('informe_profesor',
  '{"objeto": "Docente Uno", "docente": 1, "archivo": "Informe_2526_Uno_Docente.pdf"}') ->> 'codigo') $$, 'sí el informe de un profesor/a');

set local role postgres; select pg_temp.como('direccion'); set local role authenticated;
select throws_ok($$ select public.registrar_descarga('csv', '{"objeto": "Registro de descargas", "vista": "descargas", "archivo": "r.csv"}') $$,
  '42501', 'Solo para administración', 'el registro de descargas solo lo exporta administración');
select throws_ok($$ select public.registrar_descarga('otro', '{"objeto": "x", "archivo": "x"}') $$, '22023', 'Tipo de descarga no válido', 'tipo desconocido');
select throws_ok($$ select public.registrar_descarga('csv', '{"vista": "alumnos", "archivo": "a.csv"}') $$, '22023', 'Datos de la descarga no válidos', 'sin de qué es');
select throws_ok($$ select public.registrar_descarga('csv', '{"objeto": "x", "vista": "otra", "archivo": "a.csv"}') $$, '22023', 'Vista de exportación no válida', 'vista desconocida');
select throws_ok($$ select public.registrar_descarga('zip', '{"objeto": "Profesorado", "archivo": "z.zip"}') $$, '22023', 'Un ZIP necesita la lista de sus informes', 'un ZIP sin informes');

-- Cada descarga, anotada con su código ----------------------------------------------------------------------------------
create temp table r1 as select public.registrar_descarga('csv',
  '{"objeto": "Familias", "vista": "familias", "filtros": {"Etapa": "PAI"}, "archivo": "Encuestas_2526_Familias_Etapa-PAI.csv"}') as r;
select matches((select r ->> 'codigo' from r1), '^[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}$', 'código de 8 caracteres sin los que se confunden');
select is((select r ->> 'nombre' from r1), 'Dirección', 'devuelve el nombre de quien descarga, para el pie');
select ok((select (r ->> 'fecha')::timestamptz between now() - interval '1 minute' and now() + interval '1 minute' from r1), 'y la hora del servidor');
select is(pg_temp.ultima() ->> 'codigo', (select r ->> 'codigo' from r1), 'queda en el registro con su código');
select is(pg_temp.ultima() - 'codigo', '{"tipo": "csv", "vista": "familias", "objeto": "Familias", "nombre": "Dirección", "archivo": "Encuestas_2526_Familias_Etapa-PAI.csv", "filtros": {"Etapa": "PAI"}}'::jsonb,
  'con el tipo, de qué es, los filtros y el archivo');
set local role postgres;
select is((select usuario_id from public.registro_actividad where accion = 'descarga' order by id desc limit 1), '00000000-0000-0000-0000-00000000000b'::uuid,
  'y con quién la hizo');
select pg_temp.como('direccion'); set local role authenticated;
select isnt((public.registrar_descarga('csv', '{"objeto": "Familias", "vista": "familias", "archivo": "a.csv"}') ->> 'codigo'), (select r ->> 'codigo' from r1),
  'la misma descarga otra vez lleva otro código');

create temp table z as select public.registrar_descarga('zip', '{"objeto": "Profesorado (3 informes)", "archivo": "Informes_profesorado_2526.zip",
  "informes": [{"objeto": "Docente Uno", "docente": 1}, {"objeto": "Docente Dos", "docente": 2}, {"objeto": "María García", "docente": 3}]}') as r;
select is((select jsonb_array_length(r -> 'informes') from z), 3, 'ZIP: un código por informe');
select is((select count(distinct c) from (select r ->> 'codigo' as c from z union all select i ->> 'codigo' from z, jsonb_array_elements(r -> 'informes') i) x)::int, 4,
  'distintos entre sí y del código del ZIP');
select is((select jsonb_agg(i ->> 'objeto') from jsonb_array_elements(pg_temp.ultima() -> 'informes') i), '["Docente Uno", "Docente Dos", "María García"]'::jsonb,
  'el registro del ZIP lista sus informes');
set local role postgres;
insert into cod select 'zip_dentro', r -> 'informes' -> 2 ->> 'codigo' from z;
insert into cod select 'familias', r ->> 'codigo' from r1;

-- Pestaña «Descargas» ---------------------------------------------------------------------------------------------------
select pg_temp.como('direccion'); set local role authenticated;
select throws_ok($$ select public.admin_descargas() $$, '42501', 'Solo para administración', 'dirección no ve el registro de descargas');
set local role postgres; select pg_temp.como('admin', 'aal2'); set local role authenticated;
select is((public.admin_descargas() ->> 'total')::int, 4, 'administración ve todas');
select is((select jsonb_agg(f ->> 'objeto') from jsonb_array_elements(public.admin_descargas(jsonb_build_object('codigo', lower((select valor from cod where nombre = 'familias')))) -> 'filas') f),
  '["Familias"]'::jsonb, 'búsqueda por código (sin distinguir mayúsculas)');
select is((select jsonb_agg(f ->> 'tipo') from jsonb_array_elements(public.admin_descargas(jsonb_build_object('codigo', (select valor from cod where nombre = 'zip_dentro'))) -> 'filas') f),
  '["zip"]'::jsonb, 'el código de un informe de un ZIP lleva a su ZIP');
select is((public.admin_descargas('{"objeto": "garcia"}') ->> 'total')::int, 1, 'persona del informe, sin acentos y también dentro de un ZIP');
select is((public.admin_descargas('{"tipo": "csv"}') ->> 'total')::int, 2, 'por tipo');
select is((public.admin_descargas('{"persona": "00000000-0000-0000-0000-00000000000c"}') ->> 'total')::int, 1, 'por persona que descarga');
select is((public.admin_descargas(jsonb_build_object('desde', to_char(now() + interval '1 day', 'YYYY-MM-DD'))) ->> 'total')::int, 0, 'por fechas');
select ok(not exists (select 1 from jsonb_array_elements(public.admin_registro(1000)) e where e ->> 'accion' = 'descarga'),
  'la actividad deja fuera las descargas');

-- Nadie lo cambia ni lo borra ---------------------------------------------------------------------------------------------
select ok(not has_table_privilege('authenticated', 'public.registro_actividad', 'update')
          and not has_table_privilege('authenticated', 'public.registro_actividad', 'delete')
          and not has_table_privilege('authenticated', 'public.registro_actividad', 'insert'), 'desde la aplicación no se escribe en el registro');
set local role postgres;
select throws_ok($$ update public.registro_actividad set detalle = detalle || '{"codigo": "AAAA-AAAA"}' where accion = 'descarga' $$,
  '42501', 'El registro de descargas no se puede cambiar', 'ni siquiera con permisos de base de datos se cambia una descarga');
select throws_ok($$ delete from public.registro_actividad where accion = 'descarga' $$, '42501', 'El registro de descargas no se puede borrar', 'ni se borra');

select * from finish();
rollback;
