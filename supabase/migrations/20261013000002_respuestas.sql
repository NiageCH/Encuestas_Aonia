-- Respuestas anónimas en el esquema privado, que PostgREST no expone.
-- Además tienen RLS activado sin ninguna política: ni anon ni authenticated pueden
-- leerlas aunque el esquema llegara a exponerse. Solo las RPC (security definer) y
-- la ETL (service_role) acceden.

create table privado.respuesta (
  id                   bigint generated always as identity primary key,
  cuestionario_id      integer not null references public.cuestionario on delete cascade,
  grupo_id             integer references public.grupo,     -- alumnos
  etapa                text references public.etapa,         -- solo familias
  idioma_origen        text not null default 'es' check (idioma_origen in ('es', 'en')),
  docente              boolean,                              -- personal
  antiguedad           text check (antiguedad in ('primer_ano', 'mas_de_un_ano')),
  departamento_equipo  text,                                 -- personal, si el fichero lo trae
  -- La etapa se toma del grupo cuando hay grupo; nunca se guardan las dos.
  check (grupo_id is null or etapa is null)
);

create index on privado.respuesta (cuestionario_id);
create index on privado.respuesta (grupo_id);

-- Coherencia con el colectivo del cuestionario.
create function privado.validar_respuesta() returns trigger
language plpgsql set search_path = '' as $$
declare
  c public.cuestionario;
  g public.grupo;
begin
  select * into c from public.cuestionario where id = new.cuestionario_id;
  if c.colectivo = 'alumnos' then
    if new.grupo_id is null then
      raise exception 'Una respuesta de alumnos necesita grupo';
    end if;
    select * into g from public.grupo where id = new.grupo_id;
    if g.curso_id <> c.curso_id or g.etapa <> c.etapa then
      raise exception 'El grupo % no corresponde al curso o la etapa del cuestionario', g.nombre;
    end if;
    if new.docente is not null or new.antiguedad is not null or new.departamento_equipo is not null then
      raise exception 'Los segmentos de personal no aplican a alumnos';
    end if;
  elsif c.colectivo = 'familias' then
    if new.grupo_id is not null or new.docente is not null or new.antiguedad is not null
       or new.departamento_equipo is not null then
      raise exception 'Una respuesta de familias solo lleva etapa';
    end if;
  else
    if new.grupo_id is not null or new.etapa is not null then
      raise exception 'Una respuesta de personal no lleva grupo ni etapa';
    end if;
  end if;
  return new;
end $$;

create trigger respuesta_validar
  before insert or update on privado.respuesta
  for each row execute function privado.validar_respuesta();

create table privado.respuesta_item (
  id             bigint generated always as identity primary key,
  respuesta_id   bigint not null references privado.respuesta on delete cascade,
  pregunta_id    integer not null references public.pregunta,
  asignatura_id  integer references public.asignatura,
  valor          smallint,
  ns_nc          boolean not null default false,
  check (ns_nc = (valor is null)),
  unique nulls not distinct (respuesta_id, pregunta_id, asignatura_id)
);

create index on privado.respuesta_item (pregunta_id);
create index on privado.respuesta_item (respuesta_id);

-- El valor está dentro de la escala, la pregunta pertenece al cuestionario y la
-- asignatura aparece si y solo si la pregunta es por asignatura.
create function privado.validar_respuesta_item() returns trigger
language plpgsql set search_path = '' as $$
declare
  p public.pregunta;
  pc public.pregunta_cuestionario;
begin
  select * into p from public.pregunta where id = new.pregunta_id;
  select pc2.* into pc
  from public.pregunta_cuestionario pc2
  join privado.respuesta r on r.cuestionario_id = pc2.cuestionario_id
  where r.id = new.respuesta_id and pc2.pregunta_id = new.pregunta_id;
  if not found then
    raise exception 'La pregunta % no pertenece al cuestionario de la respuesta', p.codigo_diccionario;
  end if;
  if p.tipo = 'seleccion_multiple' then
    raise exception 'La selección múltiple va en respuesta_opcion';
  end if;
  if new.valor is not null and (new.valor < p.escala_min or new.valor > p.escala_max) then
    raise exception 'Valor % fuera de la escala de % a % en %',
      new.valor, p.escala_min, p.escala_max, p.codigo_diccionario;
  end if;
  if pc.por_asignatura <> (new.asignatura_id is not null) then
    raise exception 'La pregunta % % lleva asignatura', p.codigo_diccionario,
      case when pc.por_asignatura then 'sí' else 'no' end;
  end if;
  return new;
end $$;

create trigger respuesta_item_validar
  before insert or update on privado.respuesta_item
  for each row execute function privado.validar_respuesta_item();

create table privado.respuesta_opcion (
  respuesta_id  bigint not null references privado.respuesta on delete cascade,
  pregunta_id   integer not null,
  opcion_id     integer not null,
  primary key (respuesta_id, opcion_id),
  foreign key (opcion_id, pregunta_id) references public.opcion (id, pregunta_id)
);

create index on privado.respuesta_opcion (pregunta_id);

alter table privado.respuesta        enable row level security;
alter table privado.respuesta_item   enable row level security;
alter table privado.respuesta_opcion enable row level security;

revoke all on all tables in schema privado from public, anon, authenticated;
grant select, insert, update, delete on all tables in schema privado to service_role;
