-- Estado vacío fiable (26/10/2026). La web decidía si había resultados leyendo el catálogo directamente; las políticas
-- de seguridad devuelven una lista vacía, sin error, a quien no puede leerlo (por ejemplo, un administrador cuya
-- sesión todavía no ha pasado el doble factor), y la pantalla lo mostraba como «Todavía no hay resultados».
-- Esta función hace la misma pregunta, pero exige un perfil activo y el doble factor del administrador: si no los hay,
-- da error (42501) en lugar de una lista vacía, y la web puede decir «No tienes acceso a estos datos».

create function public.colectivos_cargados(p_curso text) returns text[]
language plpgsql stable security definer set search_path = '' as $$
begin
  perform permisos.exigir();
  return coalesce((select array_agg(distinct c.colectivo order by c.colectivo)
                   from public.cuestionario c join public.curso cu on cu.id = c.curso_id where cu.nombre = p_curso), '{}');
end $$;

revoke execute on function public.colectivos_cargados(text) from public, anon;
grant execute on function public.colectivos_cargados(text) to authenticated;
