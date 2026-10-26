-- Identificador aleatorio en las respuestas (decisión del 26/10/2026). Hasta ahora era correlativo: aunque
-- ninguna función lo muestra, quien administra la base de datos podía ver en qué orden se cargaron las
-- respuestas (en 2025/26, el orden de las filas de Encuesta Fácil, que suele ser el de llegada).
--
-- Desde ahora, privado.respuesta y privado.respuesta_item toman un número al azar. Las respuestas que ya hay se
-- renumeran y se vuelven a escribir en orden aleatorio, todas en esta misma transacción: así tampoco el orden
-- físico de las filas ni el número de transacción que las escribió conservan el orden original.

create function privado.id_aleatorio() returns bigint
language sql volatile set search_path = '' as $$
  select ('x' || encode(extensions.gen_random_bytes(8), 'hex'))::bit(64)::bigint & 9223372036854775807
$$;

alter table privado.respuesta alter column id drop identity;
alter table privado.respuesta alter column id set default privado.id_aleatorio();
alter table privado.respuesta_item alter column id drop identity;
alter table privado.respuesta_item alter column id set default privado.id_aleatorio();

-- Renumerar y reescribir en orden aleatorio lo que ya existe.
create temp table m on commit drop as select id as viejo, privado.id_aleatorio() as nuevo from privado.respuesta;
create temp table r_ on commit drop as
  select m.nuevo as id, r.cuestionario_id, r.grupo_id, r.idioma_origen, r.docente, r.antiguedad, r.departamento_equipo
  from privado.respuesta r join m on m.viejo = r.id;
create temp table i_ on commit drop as
  select privado.id_aleatorio() as id, m.nuevo as respuesta_id, i.pregunta_id, i.asignatura_id, i.valor, i.ns_nc, i.departamento_id
  from privado.respuesta_item i join m on m.viejo = i.respuesta_id;
create temp table o_ on commit drop as
  select m.nuevo as respuesta_id, o.pregunta_id, o.opcion_id from privado.respuesta_opcion o join m on m.viejo = o.respuesta_id;
create temp table d_ on commit drop as
  select m.nuevo as respuesta_id, d.asignatura_id, d.docente_id from privado.respuesta_docente d join m on m.viejo = d.respuesta_id;
create temp table e_ on commit drop as
  select m.nuevo as respuesta_id, e.etapa from privado.respuesta_etapa e join m on m.viejo = e.respuesta_id;
create temp table t_ on commit drop as
  select m.nuevo as respuesta_id, t.tramo from privado.respuesta_tramo t join m on m.viejo = t.respuesta_id;

truncate privado.respuesta cascade;

insert into privado.respuesta (id, cuestionario_id, grupo_id, idioma_origen, docente, antiguedad, departamento_equipo)
  select id, cuestionario_id, grupo_id, idioma_origen, docente, antiguedad, departamento_equipo from r_ order by random();
insert into privado.respuesta_item (id, respuesta_id, pregunta_id, asignatura_id, valor, ns_nc, departamento_id)
  select id, respuesta_id, pregunta_id, asignatura_id, valor, ns_nc, departamento_id from i_ order by random();
insert into privado.respuesta_opcion (respuesta_id, pregunta_id, opcion_id) select * from o_ order by random();
insert into privado.respuesta_docente (respuesta_id, asignatura_id, docente_id) select * from d_ order by random();
insert into privado.respuesta_etapa (respuesta_id, etapa) select * from e_ order by random();
insert into privado.respuesta_tramo (respuesta_id, tramo) select * from t_ order by random();

-- Comprobación: no se ha perdido nada.
do $$
begin
  if (select count(*) from privado.respuesta) <> (select count(*) from r_)
     or (select count(*) from privado.respuesta_item) <> (select count(*) from i_)
     or (select count(*) from privado.respuesta_opcion) <> (select count(*) from o_)
     or (select count(*) from privado.respuesta_docente) <> (select count(*) from d_)
     or (select count(*) from privado.respuesta_etapa) <> (select count(*) from e_)
     or (select count(*) from privado.respuesta_tramo) <> (select count(*) from t_) then
    raise exception 'La renumeración de las respuestas no cuadra: no se cambia nada';
  end if;
end $$;
