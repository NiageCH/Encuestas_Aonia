-- Eliminar usuarios (decisión del 26/10/2026). Hasta ahora solo se podían desactivar.
-- Eliminar borra la cuenta de acceso y, en cascada, su perfil, su doble factor, sus sesiones abiertas y el código de una
-- invitación pendiente (que deja de servir). El registro de actividad es la trazabilidad del colegio y no se borra: sus
-- acciones pasadas conservan el nombre y el correo que tenía, tanto si las hizo como si iban dirigidas a él, y la
-- eliminación queda anotada con quién la hizo y cuándo. La relación del registro con el usuario es «a nulo» (migración 3).
-- Todo en una sola operación: o se elimina y se anota, o no cambia nada.

alter table public.registro_actividad
  add column usuario_nombre text,
  add column usuario_correo text;
comment on column public.registro_actividad.usuario_nombre is 'Nombre de quien actuó, guardado al eliminar su cuenta (usuario_id pasa a nulo)';
comment on column public.registro_actividad.usuario_correo is 'Correo de quien actuó, guardado al eliminar su cuenta';

create function public.admin_eliminar_usuario(p_id uuid, p_correo text)
returns void
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_yo     public.usuario_perfil := privado.exigir_admin();
  v_perfil public.usuario_perfil;
  v_correo text;
begin
  -- Bloquea a los administradores para que dos eliminaciones a la vez no dejen el colegio sin ninguno.
  perform 1 from public.usuario_perfil where rol = 'administrador' for update;
  select p.* into v_perfil from public.usuario_perfil p where p.id = p_id for update;
  if not found then
    raise exception 'Usuario no encontrado' using errcode = 'P0002';
  end if;
  select u.email into v_correo from auth.users u where u.id = p_id;
  if p_id = v_yo.id then
    raise exception 'No puedes eliminarte a ti mismo';
  end if;
  if lower(trim(coalesce(p_correo, ''))) <> lower(coalesce(v_correo, '')) then
    raise exception 'El correo escrito no coincide con el del usuario: no se ha eliminado' using errcode = '22023';
  end if;
  if v_perfil.rol = 'administrador' and v_perfil.activo
     and not exists (select 1 from public.usuario_perfil where rol = 'administrador' and activo and id <> p_id) then
    raise exception 'No se puede eliminar al último administrador activo';
  end if;

  -- Como autor: nombre y correo en sus columnas (usuario_id pasará a nulo, la relación no es en cascada).
  update public.registro_actividad set usuario_nombre = v_perfil.nombre, usuario_correo = v_correo where usuario_id = p_id;
  -- Como destinatario («X invitó a Y»): el detalle ya lleva el nombre que tenía; se le añade el correo.
  update public.registro_actividad set detalle = detalle || jsonb_build_object('correo', v_correo)
  where detalle ->> 'usuario' = p_id::text and not detalle ? 'correo';
  delete from auth.users where id = p_id;
  perform privado.registrar('eliminacion', jsonb_build_object('usuario', p_id, 'nombre', v_perfil.nombre, 'correo', v_correo,
                                                              'rol', v_perfil.rol, 'etapa', v_perfil.etapa));
end $$;

revoke execute on function public.admin_eliminar_usuario(uuid, text) from public, anon;
grant execute on function public.admin_eliminar_usuario(uuid, text) to authenticated;

-- Registro: quien actuó, también si ya no existe (con el nombre guardado al eliminarlo).
create or replace function public.admin_registro(p_limite integer default 200)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_admin();
  return coalesce((
    select jsonb_agg(x order by x.fecha desc)
    from (
      select r.fecha, r.accion, r.detalle,
             coalesce(p.nombre, r.usuario_nombre, u.email, '(usuario eliminado)') as usuario,
             r.usuario_id is null as usuario_eliminado
      from public.registro_actividad r
      left join public.usuario_perfil p on p.id = r.usuario_id
      left join auth.users u on u.id = r.usuario_id
      order by r.fecha desc
      limit least(greatest(p_limite, 1), 1000)
    ) x
  ), '[]');
end $$;
