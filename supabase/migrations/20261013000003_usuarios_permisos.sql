-- Perfiles, registro de actividad, funciones de permisos y RLS. Especificación §4 y §6.

create type public.rol_usuario as enum ('administrador', 'direccion', 'coordinacion');

create table public.usuario_perfil (
  id              uuid primary key references auth.users on delete cascade,
  nombre          text not null,
  rol             public.rol_usuario not null,
  etapa           text references public.etapa,
  activo          boolean not null default true,
  ultimo_acceso   timestamptz,
  creado_en       timestamptz not null default now(),
  check ((rol = 'coordinacion') = (etapa is not null))
);

-- Solo se escribe desde el servidor (RPC o trigger).
create table public.registro_actividad (
  id          bigint generated always as identity primary key,
  usuario_id  uuid references auth.users on delete set null,
  accion      text not null,
  detalle     jsonb not null default '{}',
  fecha       timestamptz not null default now()
);

create index on public.registro_actividad (fecha desc);

create function privado.registrar(p_accion text, p_detalle jsonb default '{}')
returns void
language sql security definer set search_path = '' as $$
  insert into public.registro_actividad (usuario_id, accion, detalle)
  values (auth.uid(), p_accion, coalesce(p_detalle, '{}'));
$$;

-- Funciones de permisos. Esquema propio, no expuesto por la API, para poder usarlas
-- en las políticas RLS sin dar acceso a privado.
create schema permisos;
revoke all on schema permisos from public;
grant usage on schema permisos to authenticated, service_role;

-- Perfil del usuario actual si está activo y, si es administrador, con doble factor
-- verificado en esta sesión (aal2). Si no cumple, devuelve null.
create function permisos.perfil()
returns public.usuario_perfil
language sql stable security definer set search_path = '' as $$
  select p.*
  from public.usuario_perfil p
  where p.id = auth.uid()
    and p.activo
    and (p.rol <> 'administrador' or coalesce(auth.jwt() ->> 'aal', '') = 'aal2');
$$;

create function permisos.activo() returns boolean
language sql stable security definer set search_path = '' as $$
  select (permisos.perfil()).id is not null;
$$;

create function permisos.ve_todo() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((permisos.perfil()).rol in ('administrador', 'direccion'), false);
$$;

create function permisos.es_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((permisos.perfil()).rol = 'administrador', false);
$$;

-- Para las RPC: devuelve el perfil o lanza un error con el motivo.
create function permisos.exigir()
returns public.usuario_perfil
language plpgsql stable security definer set search_path = '' as $$
declare
  p public.usuario_perfil;
begin
  select * into p from public.usuario_perfil where id = auth.uid();
  if not found or not p.activo then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  if p.rol = 'administrador' and coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception 'Doble factor obligatorio para administradores' using errcode = '42501';
  end if;
  return p;
end $$;

revoke all on all functions in schema permisos from public;
grant execute on all functions in schema permisos to authenticated, service_role;

-- RLS en todas las tablas de public. Nadie escribe desde el cliente: la carga la hace
-- la ETL con service_role (que salta RLS) y la administración irá por RPC.
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke insert, update, delete, truncate on public.%I from anon, authenticated', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;

-- Catálogo sin datos sensibles: lo lee cualquier usuario activo.
do $$
declare t text;
begin
  foreach t in array array['curso', 'colectivo', 'etapa', 'cuestionario', 'bloque', 'pregunta',
                           'opcion', 'pregunta_cuestionario', 'pregunta_comun', 'grupo',
                           'asignatura', 'departamento'] loop
    execute format('create policy lectura_usuarios_activos on public.%I for select to authenticated using (permisos.activo())', t);
  end loop;
end $$;

-- Nombres y correos de profesores y responsables: solo administración y dirección.
-- La coordinación obtiene su lista de profesores por RPC, filtrada por etapa.
create policy lectura_direccion on public.persona_responsable
  for select to authenticated using (permisos.ve_todo());
create policy lectura_direccion on public.cargo
  for select to authenticated using (permisos.ve_todo());
create policy lectura_direccion on public.asignacion_docente
  for select to authenticated using (permisos.ve_todo());

create policy lectura_propia_o_admin on public.usuario_perfil
  for select to authenticated using (id = auth.uid() or permisos.es_admin());

create policy lectura_admin on public.registro_actividad
  for select to authenticated using (permisos.es_admin());

-- Por defecto, Supabase da permisos a anon y authenticated sobre lo que se cree en
-- public. Los quitamos para tablas y funciones futuras: cada RPC concede lo suyo.
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke insert, update, delete, truncate on tables from authenticated;
alter default privileges in schema public revoke execute on functions from anon;
alter default privileges revoke execute on functions from public;
