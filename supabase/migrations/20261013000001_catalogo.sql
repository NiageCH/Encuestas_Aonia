-- Catálogo: cursos, colectivos, etapas, cuestionarios, diccionario de preguntas,
-- grupos, asignaturas y responsables. Especificación §4.
-- El curso está en todas las tablas de catálogo de cada curso. La pregunta no lleva
-- curso: su código de diccionario es estable entre cursos.

-- Esquema interno (no expuesto por la API): respuestas y funciones auxiliares.
create schema privado;
revoke all on schema privado from public, anon, authenticated;
grant usage on schema privado to service_role;

create table public.curso (
  id      smallint generated always as identity primary key,
  nombre  text not null unique check (nombre ~ '^\d{4}/\d{2}$')   -- "2025/26"
);

create table public.colectivo (
  codigo  text primary key check (codigo in ('alumnos', 'familias', 'personal')),
  nombre  text not null
);

create table public.etapa (
  codigo  text primary key check (codigo in ('infantil', 'primaria', 'pai', 'bachillerato')),
  nombre  text not null,
  orden   smallint not null unique
);

-- etapa: solo en cuestionarios de alumnos (Primaria, PAI, Bachillerato). Sirve para
-- los permisos de coordinación (§6).
create table public.cuestionario (
  id                      integer generated always as identity primary key,
  curso_id                smallint not null references public.curso,
  colectivo               text not null references public.colectivo,
  etapa                   text references public.etapa,
  codigo                  text not null,
  titulo                  text not null,
  respuestas_incompletas  integer not null default 0 check (respuestas_incompletas >= 0),
  unique (curso_id, codigo),
  check ((colectivo = 'alumnos') = (etapa is not null))
);

-- codigo: estable entre cuestionarios ("profesorado", "servicios"...), para agregar
-- un mismo bloque de varios cuestionarios.
create table public.bloque (
  id               integer generated always as identity primary key,
  cuestionario_id  integer not null references public.cuestionario on delete cascade,
  codigo           text not null,
  nombre           text not null,
  orden            smallint not null default 0,
  entra_en_media   boolean not null default true,
  unique (cuestionario_id, codigo),
  unique (id, cuestionario_id)
);

create type public.tipo_pregunta as enum ('escala', 'recomendacion', 'seleccion_multiple');

-- La escala vive en la pregunta. 7 = NS/NC no es parte de la escala: se guarda como ns_nc.
create table public.pregunta (
  id                  integer generated always as identity primary key,
  codigo_diccionario  text not null unique,
  texto_es            text not null,
  texto_en            text,
  tipo                public.tipo_pregunta not null,
  escala_min          smallint,
  escala_max          smallint,
  escala_pendiente    boolean not null default false,   -- satisfacción general de alumnos (§2)
  check (
    (tipo = 'seleccion_multiple' and escala_min is null and escala_max is null)
    or (tipo <> 'seleccion_multiple' and escala_min is not null and escala_max > escala_min)
  )
);

create table public.opcion (
  id           integer generated always as identity primary key,
  pregunta_id  integer not null references public.pregunta on delete cascade,
  codigo       text not null,
  texto_es     text not null,
  texto_en     text,
  unique (pregunta_id, codigo),
  unique (id, pregunta_id)
);

create table public.pregunta_cuestionario (
  cuestionario_id  integer not null references public.cuestionario on delete cascade,
  pregunta_id      integer not null references public.pregunta,
  bloque_id        integer not null,
  orden            smallint not null default 0,
  por_asignatura   boolean not null default false,
  primary key (cuestionario_id, pregunta_id),
  foreign key (bloque_id, cuestionario_id) references public.bloque (id, cuestionario_id)
);

-- Todas las preguntas de un bloque comparten tipo y escala.
create function privado.validar_escala_bloque() returns trigger
language plpgsql set search_path = '' as $$
begin
  if exists (
    select 1
    from public.pregunta_cuestionario pc
    join public.pregunta p on p.id = pc.pregunta_id
    join public.pregunta n on n.id = new.pregunta_id
    where pc.bloque_id = new.bloque_id
      and pc.pregunta_id <> new.pregunta_id
      and (p.tipo, p.escala_min, p.escala_max) is distinct from (n.tipo, n.escala_min, n.escala_max)
  ) then
    raise exception 'El bloque % mezcla preguntas con distinta escala', new.bloque_id;
  end if;
  return new;
end $$;

create trigger pregunta_cuestionario_escala
  before insert or update on public.pregunta_cuestionario
  for each row execute function privado.validar_escala_bloque();

-- Preguntas comunes entre colectivos para el panel general (§7.1).
create table public.pregunta_comun (
  codigo_comun  text not null,
  texto_es      text not null,
  colectivo     text not null references public.colectivo,
  pregunta_id   integer not null references public.pregunta,
  primary key (codigo_comun, colectivo, pregunta_id)
);

create table public.grupo (
  id        integer generated always as identity primary key,
  curso_id  smallint not null references public.curso,
  etapa     text not null references public.etapa,
  nivel     text not null,                -- "Y9"
  nombre    text not null,                -- "Y9 A"
  unique (curso_id, nombre)
);

create table public.asignatura (
  id        integer generated always as identity primary key,
  curso_id  smallint not null references public.curso,
  nombre    text not null,
  unique (curso_id, nombre)
);

create table public.departamento (
  id        integer generated always as identity primary key,
  curso_id  smallint not null references public.curso,
  nombre    text not null,
  unique (curso_id, nombre)
);

create table public.persona_responsable (
  id               integer generated always as identity primary key,
  nombre           text not null,
  apellidos        text not null,
  correo           text unique,
  departamento_id  integer references public.departamento
);

create type public.tipo_cargo as enum ('jefe_departamento', 'jefe_equipo', 'direccion');

-- ambito: nombre del departamento o equipo; casa con respuesta.departamento_equipo.
create table public.cargo (
  persona_id  integer not null references public.persona_responsable on delete cascade,
  curso_id    smallint not null references public.curso,
  tipo        public.tipo_cargo not null,
  ambito      text not null,
  primary key (persona_id, curso_id, tipo, ambito)
);

-- Clave de las cuatro columnas: admite codocencia y desdobles.
create table public.asignacion_docente (
  curso_id       smallint not null references public.curso,
  grupo_id       integer not null references public.grupo,
  asignatura_id  integer not null references public.asignatura,
  docente_id     integer not null references public.persona_responsable on delete cascade,
  primary key (curso_id, grupo_id, asignatura_id, docente_id)
);

create index on public.asignacion_docente (docente_id);

insert into public.colectivo (codigo, nombre) values
  ('alumnos', 'Alumnos'), ('familias', 'Familias'), ('personal', 'Personal');

insert into public.etapa (codigo, nombre, orden) values
  ('infantil', 'Infantil', 1), ('primaria', 'Primaria', 2),
  ('pai', 'PAI', 3), ('bachillerato', 'Bachillerato', 4);
