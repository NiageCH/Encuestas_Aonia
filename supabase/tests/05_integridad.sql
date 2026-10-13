-- Integridad de la carga: lo que la ETL no puede meter mal aunque lo intente.
begin;
\ir fixtures/datos_ejemplo.psql
select plan(9);

create temp table ref as select
  (select id from public.cuestionario where codigo = 'PAI_T') as pai,
  (select id from public.cuestionario where codigo = 'FAM_T') as fam,
  (select id from public.cuestionario where codigo = 'PER_T') as per,
  (select id from public.grupo where nombre = 'Y7 A') as grupo,
  (select id from public.pregunta where codigo_diccionario = 'centro_ambiente') as amb,
  (select id from public.pregunta where codigo_diccionario = 'prof_claridad') as clar,
  (select id from public.pregunta where codigo_diccionario = 'rec_alumnos') as rec,
  (select min(r.id) from privado.respuesta r join public.cuestionario c on c.id = r.cuestionario_id where c.codigo = 'PAI_T') as resp;

select throws_ok($$ insert into privado.respuesta (cuestionario_id, grupo_id)
                    select fam, grupo from ref $$,
  'P0001', 'Una respuesta de familias no lleva grupo ni segmentos de personal', 'familias sin grupo');
select throws_ok($$ insert into privado.respuesta_etapa (respuesta_id, etapa) select resp, 'pai' from ref $$,
  'P0001', 'Solo las respuestas de familias llevan etapas propias', 'las etapas propias son solo de familias');
select throws_ok($$ insert into privado.respuesta (cuestionario_id, docente) select fam, true from ref $$,
  'P0001', 'Una respuesta de familias no lleva grupo ni segmentos de personal', 'familias sin segmentos de personal');
select throws_ok($$ insert into privado.respuesta (cuestionario_id, antiguedad) select per, 'diez_anos' from ref $$,
  '23514', null, 'antigüedad solo admite primer_ano o mas_de_un_ano');
select hasnt_column('privado', 'respuesta', 'sexo', 'la respuesta no tiene columna de sexo');
select throws_ok($$ update privado.respuesta_item set valor = 7 where pregunta_id = (select amb from ref) and respuesta_id = (select resp from ref) $$,
  'P0001', null, 'un 7 no se guarda como valor: NS/NC va en ns_nc');
select throws_ok($$ update privado.respuesta_item set ns_nc = false, valor = null where pregunta_id = (select rec from ref) and respuesta_id = (select resp from ref) $$,
  '23514', null, 'un valor vacío tiene que estar marcado como NS/NC');
select throws_ok($$ insert into privado.respuesta_item (respuesta_id, pregunta_id, valor) select resp, clar, 3 from ref $$,
  'P0001', null, 'una pregunta por asignatura exige asignatura');
select throws_ok($$ insert into public.pregunta_cuestionario (cuestionario_id, pregunta_id, bloque_id)
                    select c.id, p.id, b.id from public.cuestionario c
                    join public.bloque b on b.cuestionario_id = c.id and b.codigo = 'centro'
                    join public.pregunta p on p.codigo_diccionario = 'ib_autoeval'
                    where c.codigo = 'PER_T' $$,
  'P0001', null, 'un bloque no mezcla escalas distintas');

select * from finish();
rollback;
