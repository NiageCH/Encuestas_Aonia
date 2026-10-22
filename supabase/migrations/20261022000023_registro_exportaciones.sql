-- Exportación de cada vista (§7.6, decisión del 22/10/2026): CSV y PDF de Inicio, Alumnos, Familias y
-- Personal. Los datos salen de las mismas RPC que la pantalla (con permisos, mínimo de 5 y supresión
-- complementaria); esta función solo deja cada exportación en el registro de actividad, con la
-- vista, el formato y los filtros activos, y rechaza a quien no puede ver esa vista.

create function public.registrar_exportacion(p_vista text, p_formato text, p_filtros jsonb default '{}')
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_perfil public.usuario_perfil := permisos.exigir();
  v_filtros jsonb := coalesce(p_filtros, '{}');
begin
  if p_formato is null or p_formato not in ('csv', 'pdf') then
    raise exception 'Formato de exportación no válido' using errcode = '22023';
  end if;
  if p_vista is null or p_vista not in ('inicio', 'alumnos', 'familias', 'personal') then
    raise exception 'Vista de exportación no válida' using errcode = '22023';
  end if;
  if jsonb_typeof(v_filtros) <> 'object' or length(v_filtros::text) > 2000 then
    raise exception 'Filtros de exportación no válidos' using errcode = '22023';
  end if;
  if p_vista = 'personal' and v_perfil.rol = 'coordinacion' then
    raise exception 'Sin acceso a los resultados de personal' using errcode = '42501';
  end if;
  perform privado.registrar('exportacion', jsonb_build_object('vista', p_vista, 'formato', p_formato, 'filtros', v_filtros));
end $$;

revoke execute on function public.registrar_exportacion(text, text, jsonb) from public, anon;
grant execute on function public.registrar_exportacion(text, text, jsonb) to authenticated;
