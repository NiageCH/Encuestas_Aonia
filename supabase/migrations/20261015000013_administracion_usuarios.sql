-- Administración de usuarios (§7.5, pasos 4 y 9): lista, cambios de rol y etapa,
-- desactivar y reactivar, último acceso con aviso a los 90 días y registro de actividad.
-- Las invitaciones van por la Edge Function admin-usuarios (necesitan la clave de servicio).
-- Todo lo de aquí exige un administrador activo con doble factor (aal2).

-- Último acceso: se copia de auth.users en cada inicio de sesión.
create function privado.copiar_ultimo_acceso() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.last_sign_in_at is distinct from old.last_sign_in_at then
    update public.usuario_perfil set ultimo_acceso = new.last_sign_in_at where id = new.id;
  end if;
  return new;
end $$;

create trigger usuario_ultimo_acceso
  after update of last_sign_in_at on auth.users
  for each row execute function privado.copiar_ultimo_acceso();

create function privado.exigir_admin() returns public.usuario_perfil
language plpgsql stable security definer set search_path = '' as $$
declare
  p public.usuario_perfil := permisos.exigir();
begin
  if p.rol <> 'administrador' then
    raise exception 'Solo para administradores' using errcode = '42501';
  end if;
  return p;
end $$;

-- Lista de usuarios con su estado. "pendiente": invitado que aún no ha entrado.
create function public.admin_usuarios()
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', p.id, 'nombre', p.nombre, 'correo', u.email, 'rol', p.rol, 'etapa', p.etapa,
      'estado', case when not p.activo then 'desactivado'
                     when u.last_sign_in_at is null then 'pendiente'
                     else 'activo' end,
      'invitado', coalesce(u.invited_at, u.created_at),
      'ultimo_acceso', coalesce(p.ultimo_acceso, u.last_sign_in_at),
      'aviso_90_dias', p.activo and u.last_sign_in_at is not null and u.last_sign_in_at < now() - interval '90 days',
      'doble_factor', exists (select 1 from auth.mfa_factors f where f.user_id = p.id and f.status = 'verified'))
      order by p.activo desc, p.nombre)
    from public.usuario_perfil p
    join auth.users u on u.id = p.id
  ), '[]');
end $$;

-- Cambiar rol, etapa o estado. Un administrador no puede quitarse a sí mismo el rol ni
-- desactivarse, y siempre debe quedar al menos un administrador activo.
create function public.admin_actualizar_usuario(p_id uuid, p_rol public.rol_usuario, p_etapa text, p_activo boolean)
returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_yo     public.usuario_perfil := privado.exigir_admin();
  v_antes  public.usuario_perfil;
begin
  select * into v_antes from public.usuario_perfil where id = p_id for update;
  if not found then
    raise exception 'Usuario no encontrado' using errcode = 'P0002';
  end if;
  if p_id = v_yo.id and (p_rol <> 'administrador' or not p_activo) then
    raise exception 'No puedes quitarte el rol de administrador ni desactivarte a ti mismo';
  end if;
  if (p_rol = 'coordinacion') <> (p_etapa is not null) then
    raise exception 'La coordinación necesita etapa, y los demás roles no la llevan';
  end if;

  update public.usuario_perfil set rol = p_rol, etapa = p_etapa, activo = p_activo where id = p_id;

  if not exists (select 1 from public.usuario_perfil where rol = 'administrador' and activo) then
    raise exception 'Tiene que quedar al menos un administrador activo';
  end if;

  if v_antes.activo and not p_activo then
    perform privado.registrar('desactivacion', jsonb_build_object('usuario', p_id, 'nombre', v_antes.nombre));
  elsif not v_antes.activo and p_activo then
    perform privado.registrar('reactivacion', jsonb_build_object('usuario', p_id, 'nombre', v_antes.nombre));
  end if;
  if v_antes.rol is distinct from p_rol or v_antes.etapa is distinct from p_etapa then
    perform privado.registrar('cambio_rol', jsonb_build_object('usuario', p_id, 'nombre', v_antes.nombre,
      'antes', jsonb_build_object('rol', v_antes.rol, 'etapa', v_antes.etapa),
      'despues', jsonb_build_object('rol', p_rol, 'etapa', p_etapa)));
  end if;
end $$;

-- Registro de actividad con el nombre de quien actuó.
create function public.admin_registro(p_limite integer default 200)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_admin();
  return coalesce((
    select jsonb_agg(x order by x.fecha desc)
    from (
      select r.fecha, r.accion, r.detalle, coalesce(p.nombre, u.email, '(usuario eliminado)') as usuario
      from public.registro_actividad r
      left join public.usuario_perfil p on p.id = r.usuario_id
      left join auth.users u on u.id = r.usuario_id
      order by r.fecha desc
      limit least(greatest(p_limite, 1), 1000)
    ) x
  ), '[]');
end $$;

-- Lo usa la Edge Function (con la clave de servicio) tras invitar: perfil y registro con el
-- administrador que invita como autor.
create function public.admin_registrar_invitacion(p_admin uuid, p_usuario uuid, p_nombre text, p_rol public.rol_usuario,
                                                  p_etapa text, p_reenvio boolean default false)
returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  if not p_reenvio then
    insert into public.usuario_perfil (id, nombre, rol, etapa) values (p_usuario, p_nombre, p_rol, p_etapa);
  end if;
  insert into public.registro_actividad (usuario_id, accion, detalle)
  values (p_admin, case when p_reenvio then 'reenvio_invitacion' else 'invitacion' end,
          jsonb_build_object('usuario', p_usuario, 'nombre', p_nombre, 'rol', p_rol, 'etapa', p_etapa));
end $$;

revoke execute on function public.admin_usuarios() from public, anon;
revoke execute on function public.admin_actualizar_usuario(uuid, public.rol_usuario, text, boolean) from public, anon;
revoke execute on function public.admin_registro(integer) from public, anon;
revoke execute on function public.admin_registrar_invitacion(uuid, uuid, text, public.rol_usuario, text, boolean) from public, anon, authenticated;
grant execute on function public.admin_usuarios() to authenticated;
grant execute on function public.admin_actualizar_usuario(uuid, public.rol_usuario, text, boolean) to authenticated;
grant execute on function public.admin_registro(integer) to authenticated;
grant execute on function public.admin_registrar_invitacion(uuid, uuid, text, public.rol_usuario, text, boolean) to service_role;

-- Para la Edge Function: ¿existe ya un usuario con este correo? Evita invitar dos veces y, sobre
-- todo, deshacer (borrar) por error a un usuario que ya existía.
create function public.admin_id_por_correo(p_correo text)
returns uuid
language sql stable security definer set search_path = '' as $$
  select id from auth.users where lower(email) = lower(trim(p_correo));
$$;

revoke execute on function public.admin_id_por_correo(text) from public, anon, authenticated;
grant execute on function public.admin_id_por_correo(text) to service_role;
