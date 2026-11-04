-- Destinatarios de prueba fijos (04/11/2026): mientras el envío esté en modo «pruebas», los correos solo pueden ir a
-- rodrigo@niage.es o a mark.polko@sfpaula.com, elegidos en un desplegable, con «[PRUEBA]» en el asunto. Nada al
-- profesorado. La Edge Function enviar-informes comprueba la misma lista otra vez.
-- privado.correo_niage conserva el nombre (la usan privado.destinatarios y public.admin_envio_crear) y pasa a ser
-- esa lista cerrada.
create or replace function privado.correo_niage(p_correo text) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(lower(btrim(p_correo)) in ('rodrigo@niage.es', 'mark.polko@sfpaula.com'), false);
$$;
