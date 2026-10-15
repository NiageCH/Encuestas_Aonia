-- Doble factor de administradores: obligatorio salvo que la base de datos tenga, de forma
-- explícita, app.mfa_admin_obligatorio = 'off'. Ese ajuste solo se pone en el entorno local
-- de desarrollo (decisión del 15/10/2026, para probar las pantallas de administración); no
-- está en ninguna migración, así que en producción el doble factor sigue siendo obligatorio.
--   Local:      alter database postgres set app.mfa_admin_obligatorio = 'off';
--   Deshacer:   alter database postgres reset app.mfa_admin_obligatorio;

create function permisos.mfa_obligatorio() returns boolean
language sql stable set search_path = '' as $$
  select coalesce(current_setting('app.mfa_admin_obligatorio', true), '') <> 'off';
$$;

create or replace function permisos.perfil()
returns public.usuario_perfil
language sql stable security definer set search_path = '' as $$
  select p.*
  from public.usuario_perfil p
  where p.id = auth.uid()
    and p.activo
    and (p.rol <> 'administrador' or not permisos.mfa_obligatorio() or coalesce(auth.jwt() ->> 'aal', '') = 'aal2');
$$;

create or replace function permisos.exigir()
returns public.usuario_perfil
language plpgsql stable security definer set search_path = '' as $$
declare
  p public.usuario_perfil;
begin
  select * into p from public.usuario_perfil where id = auth.uid();
  if not found or not p.activo then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  if p.rol = 'administrador' and permisos.mfa_obligatorio() and coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
    raise exception 'Doble factor obligatorio para administradores' using errcode = '42501';
  end if;
  return p;
end $$;

-- La aplicación y la Edge Function preguntan aquí si el doble factor está activo.
create function public.mfa_admin_obligatorio() returns boolean
language sql stable security definer set search_path = '' as $$
  select permisos.mfa_obligatorio();
$$;

grant execute on function permisos.mfa_obligatorio() to authenticated, service_role;
revoke execute on function public.mfa_admin_obligatorio() from public, anon;
grant execute on function public.mfa_admin_obligatorio() to authenticated, service_role;
