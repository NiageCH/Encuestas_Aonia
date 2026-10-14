-- Anonimato (§5): mínimo de 5, supresión complementaria e intentos de saltarla por resta
-- y por combinación de filtros.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(40);

-- Comprueba el invariante de la supresión complementaria en un resultado: en cada línea
-- con el total visible, el número de partes suprimidas es 0 o al menos 2. Con dos
-- dimensiones, las líneas son los dos márgenes (total general) y cada fila y columna
-- (con su margen como total).
create function pg_temp.sin_parte_aislada(p jsonb) returns boolean
language sql as $$
  with partes as (
    select e -> 'clave' as clave, (e ->> 'suprimido')::boolean as sup from jsonb_array_elements(p -> 'partes') e
  ), dims as (
    select jsonb_array_elements_text(p -> 'dimensiones') as d
  ), nd as (select count(*) as n from dims
  ), lineas as (
    -- partes con una sola clave de salida: su total es el total general
    select 'margen:' || d as linea, (p -> 'total' ->> 'suprimido')::boolean as total_sup, sup
    from partes, dims
    where clave ? d and not exists (select 1 from dims d2 where d2.d <> dims.d and clave ? d2.d)
    union all
    -- celdas de dos dimensiones: su total es el margen de su fila o columna
    select 'linea:' || d || '=' || (clave ->> d),
           coalesce((select m.sup from partes m where m.clave = jsonb_build_object(d, partes.clave ->> d)), true),
           sup
    from partes, dims, nd
    where nd.n = 2 and (select count(*) from dims d2 where clave ? d2.d) = 2
  )
  select not exists (
    select 1 from lineas where not total_sup group by linea having count(*) filter (where sup) = 1
  );
$$;

create function pg_temp.parte(p jsonb, p_clave jsonb) returns jsonb
language sql as $$ select e from jsonb_array_elements(p -> 'partes') e where e -> 'clave' = p_clave $$;

grant execute on function pg_temp.sin_parte_aislada(jsonb), pg_temp.parte(jsonb, jsonb) to authenticated;

-- Valores reales para comprobar la media de grupo y el intento de resta (como postgres).
create temp table verdad as
with prof as (
  select g.nombre as grupo, a.nombre as asig, i.valor
  from privado.respuesta_item i
  join privado.respuesta r on r.id = i.respuesta_id
  join public.grupo g on g.id = r.grupo_id
  join public.asignatura a on a.id = i.asignatura_id
  where g.curso_id = (select id from public.curso where nombre = '2000/01') and i.valor is not null
)
select (select avg(valor) from prof where grupo = 'Y7 A') as y7a_media,
       (select sum(valor) from prof where grupo = 'Y7 A' and asig = 'Lengua') as y7a_lengua_suma,
       (select count(*) from prof where grupo = 'Y7 A' and asig = 'Lengua') as y7a_lengua_n;
grant select on verdad to authenticated;

select ok(not pg_temp.sin_parte_aislada('{"dimensiones":["grupo"],"total":{"suprimido":false},
  "partes":[{"clave":{"grupo":"X"},"suprimido":true},{"clave":{"grupo":"Y"},"suprimido":false}]}'),
  'control: el comprobador detecta una parte suprimida aislada');

reset role; select pg_temp.como('direccion'); set local role authenticated;

-- Mínimo de 5 y supresión complementaria por grupos
create temp table r_grupos as
  select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"personas"}', '{grupo}') as r;
select is((select (r -> 'total' ->> 'n')::int from r_grupos), 29, 'el total de alumnos es visible');
select is((select pg_temp.parte(r, '{"grupo":"Y7 C"}') ->> 'motivo' from r_grupos), 'menos_de_5', 'Y7 C (3) se suprime por mínimo');
select is((select pg_temp.parte(r, '{"grupo":"Y7 D"}') ->> 'motivo' from r_grupos), 'complementaria',
  'Y7 D (6, la más pequeña visible) se suprime por complementaria');
select is((select (pg_temp.parte(r, '{"grupo":"Y7 B"}') ->> 'n')::int from r_grupos), 8, 'Y7 B (8) es visible');
select ok((select not (pg_temp.parte(r, '{"grupo":"Y7 C"}') ?| array['n', 'media', 'distribucion', 'n_personas']) from r_grupos),
  'una parte suprimida no devuelve n, media ni distribución');
select ok((select pg_temp.sin_parte_aislada(r) from r_grupos), 'por grupos no queda ninguna parte suprimida aislada');

-- Ataque por resta: total menos partes visibles no da el valor de un solo grupo
select is((select (r -> 'total' ->> 'n')::int - sum((e ->> 'n')::int)::int
           from r_grupos, jsonb_array_elements(r -> 'partes') e where not (e ->> 'suprimido')::boolean group by r),
          9, 'la resta solo da la suma de Y7 C y Y7 D juntos, nunca uno solo');

-- Ataque pidiendo directamente la parte suprimida por complementaria
select is((public.resultados('{"curso":"2000/01","colectivo":"alumnos","grupo":"Y7 D"}', '{"tipo":"personas"}') -> 'total' ->> 'motivo'),
  'complementaria', 'pedir Y7 D directamente no lo destapa');
select is((public.resultados('{"curso":"2000/01","colectivo":"alumnos","grupo":"Y7 D"}', '{"tipo":"recomendacion"}') -> 'total' ->> 'suprimido'),
  'true', 'Y7 D tampoco se destapa con otra métrica');
select is((public.resultados('{"curso":"2000/01","colectivo":"alumnos","grupo":"Y7 C"}', '{"tipo":"satisfaccion"}') -> 'total' ->> 'motivo'),
  'menos_de_5', 'pedir Y7 C directamente sigue suprimido');
select is((public.resultados('{"curso":"2000/01","colectivo":"alumnos","grupo":"Y7 D"}', '{"tipo":"personas"}', '{asignatura}') -> 'total' ->> 'suprimido'),
  'true', 'Y7 D repartido por asignatura mantiene su total suprimido');

-- Mínimo por pregunta: el grupo es visible pero la pregunta no
select is((public.resultados('{"curso":"2000/01","colectivo":"alumnos","grupo":"Y7 B"}', '{"tipo":"personas"}') -> 'total' ->> 'n')::int,
  8, 'Y7 B es visible como grupo');
select is((public.resultados('{"curso":"2000/01","colectivo":"alumnos","grupo":"Y7 B"}', '{"tipo":"pregunta","codigo":"centro_ambiente"}') -> 'total' ->> 'motivo'),
  'menos_de_5', 'la pregunta con 4 valoraciones válidas en Y7 B se suprime');
select ok(pg_temp.sin_parte_aislada(public.resultados('{"curso":"2000/01","colectivo":"alumnos"}',
  '{"tipo":"pregunta","codigo":"centro_ambiente"}', '{grupo}')), 'una pregunta por grupos no deja partes aisladas');
select ok((select bool_and(pg_temp.sin_parte_aislada(e -> 'resultado'))
           from jsonb_array_elements(public.detalle_preguntas('{"curso":"2000/01","colectivo":"alumnos"}', 'profesorado', '{grupo,asignatura}')) e),
  'el detalle por pregunta, asignatura y grupo no deja partes aisladas');

-- Tabla asignatura por grupo (dos dimensiones, supresión iterativa)
create temp table r_tabla as
  select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"bloque","codigo":"profesorado"}', '{grupo,asignatura}') as r;
select is((select pg_temp.parte(r, '{"grupo":"Y7 A","asignatura":"Lengua"}') ->> 'motivo' from r_tabla), 'menos_de_5', 'Lengua en Y7 A (4) se suprime');
select is((select pg_temp.parte(r, '{"grupo":"Y7 A","asignatura":"Matemáticas"}') ->> 'motivo' from r_tabla), 'complementaria',
  'Matemáticas en Y7 A se suprime para proteger Lengua en Y7 A (columna)');
select is((select pg_temp.parte(r, '{"grupo":"Y7 D","asignatura":"Matemáticas"}') ->> 'motivo' from r_tabla), 'complementaria',
  'Matemáticas en Y7 D se suprime para proteger Y7 C (fila)');
select is((select pg_temp.parte(r, '{"grupo":"Y7 D"}') ->> 'motivo' from r_tabla), 'complementaria',
  'el margen de Y7 D se suprime para proteger el de Y7 C');
select is((select pg_temp.parte(r, '{"grupo":"Y7 D","asignatura":"Lengua"}') ->> 'suprimido' from r_tabla), 'false',
  'Lengua en Y7 D sigue visible: con el total de su columna oculto no permite deducir Matemáticas en Y7 D');
select is((select pg_temp.parte(r, '{"grupo":"Y7 B","asignatura":"Matemáticas"}') ->> 'suprimido' from r_tabla), 'false', 'Matemáticas en Y7 B es visible');
select ok((select pg_temp.sin_parte_aislada(r) from r_tabla), 'la tabla no deja partes aisladas en filas, columnas ni márgenes');
-- Media de un grupo con todas sus valoraciones (también las de celdas ocultas), sin que la
-- resta destape una celda asignatura y grupo oculta (§5.2)
select is((select (pg_temp.parte(r, '{"grupo":"Y7 A"}') ->> 'media')::numeric from r_tabla), (select y7a_media from verdad),
  'la media del grupo usa todas sus valoraciones, incluidas las de celdas ocultas');
select ok((select count(*) from r_tabla, jsonb_array_elements(r -> 'partes') e
           where e -> 'clave' ->> 'grupo' = 'Y7 A' and e -> 'clave' ? 'asignatura' and (e ->> 'suprimido')::boolean) >= 2,
  'si una celda del grupo queda oculta, se oculta al menos otra');
select ok((select (m ->> 'n_valoraciones')::numeric * (m ->> 'media')::numeric
                  - coalesce((select sum((e ->> 'n_valoraciones')::numeric * (e ->> 'media')::numeric)
                              from jsonb_array_elements(r -> 'partes') e
                              where e -> 'clave' ->> 'grupo' = 'Y7 A' and e -> 'clave' ? 'asignatura'
                                and not (e ->> 'suprimido')::boolean), 0)
           from r_tabla, pg_temp.parte(r, '{"grupo":"Y7 A"}') m)
          <> (select y7a_lengua_suma from verdad)
      and (select (m ->> 'n_valoraciones')::int from r_tabla, pg_temp.parte(r, '{"grupo":"Y7 A"}') m) <> (select y7a_lengua_n from verdad),
  'restar al grupo sus celdas visibles no da la suma ni el n de la celda oculta de Lengua');
select is((public.resultados('{"curso":"2000/01","colectivo":"alumnos","grupo":"Y7 A","asignatura":"Matemáticas"}',
  '{"tipo":"bloque","codigo":"profesorado"}') -> 'total' ->> 'motivo'), 'complementaria',
  'pedir directamente Matemáticas en Y7 A no lo destapa');

-- Familias: Bachillerato (3) siempre suprimido, con aviso, y su complementaria
create temp table r_fam as
  select public.resultados('{"curso":"2000/01","colectivo":"familias"}', '{"tipo":"pregunta","codigo":"centro_ambiente"}', '{etapa}') as r;
select is((select pg_temp.parte(r, '{"etapa":"bachillerato"}') ->> 'motivo' from r_fam), 'menos_de_5', 'familias de Bachillerato se suprime y se devuelve (no se omite)');
select is((select pg_temp.parte(r, '{"etapa":"infantil"}') ->> 'motivo' from r_fam), 'complementaria', 'familias de Infantil se suprime por complementaria');

-- Personal: un filtro a la vez
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal","docente":true,"antiguedad":"primer_ano"}', '{"tipo":"personas"}') $$,
  'P0001', 'Los filtros de personal no se combinan: usa uno a la vez', 'no se combinan dos filtros de personal');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal","docente":true}', '{"tipo":"personas"}', '{antiguedad}') $$,
  'P0001', 'Los filtros de personal no se combinan: usa uno a la vez', 'no se combina un filtro con un reparto por otro segmento');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal"}', '{"tipo":"personas"}', '{docente,departamento_equipo}') $$,
  'P0001', 'Los filtros de personal no se combinan: usa uno a la vez', 'no se reparte por dos segmentos a la vez');
select is((public.resultados('{"curso":"2000/01","colectivo":"personal","docente":true}', '{"tipo":"personas"}') -> 'total' ->> 'motivo'),
  'complementaria', 'docentes (20) se suprime porque no docentes (4) queda por debajo de 5');
select is((public.resultados('{"curso":"2000/01","colectivo":"personal","docente":false}', '{"tipo":"bloque","codigo":"superiores"}') -> 'total' ->> 'motivo'),
  'menos_de_5', 'el bloque Superiores de no docentes (4) se suprime');
select is((public.resultados('{"curso":"2000/01","colectivo":"personal","departamento_equipo":"Letras"}', '{"tipo":"bloque","codigo":"superiores"}') -> 'total' ->> 'n')::int,
  9, 'Superiores de un departamento con 9 personas es visible');
-- Idioma: no es un filtro; el recuento por idioma es informativo y exacto (fixture: 22 en español y 2 en inglés)
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal","idioma":"es"}', '{"tipo":"personas"}') $$,
  'P0001', 'Filtro no válido para personal: idioma', 'el idioma no es un filtro');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal"}', '{"tipo":"personas"}', '{idioma}') $$,
  'P0001', 'Dimensión no válida para personal: idioma', 'ni una dimensión: no hay resultados por idioma');
select is(public.recuento_idiomas('2000/01'), '{"en": 2, "es": 22}'::jsonb, 'el recuento por idioma es exacto (dato informativo)');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"personal","sexo":"m"}', '{"tipo":"personas"}') $$,
  'P0001', 'Filtro no válido para personal: sexo', 'no existe filtro por sexo');
select throws_ok($$ select public.resultados('{"curso":"2000/01","colectivo":"alumnos"}', '{"tipo":"personas"}', '{cuestionario,grupo,asignatura}') $$,
  'P0001', 'Como máximo dos dimensiones a la vez', 'como máximo dos dimensiones');

select * from finish();
rollback;
