-- Aviso del revisor de Supabase (auth_rls_initplan): auth.uid() en una política se evalúa en
-- cada fila. Envuelto en un select se evalúa una vez por consulta. Mismo permiso que antes.
drop policy lectura_propia_o_admin on public.usuario_perfil;
create policy lectura_propia_o_admin on public.usuario_perfil
  for select to authenticated using (id = (select auth.uid()) or permisos.es_admin());
