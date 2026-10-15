// Edge Function: invitaciones de usuarios (§7.5). Necesita la clave de servicio de Supabase,
// que nunca llega al navegador. Solo la usa un administrador activo con doble factor (aal2).
//
// POST { accion: "invitar", nombre, correo, rol, etapa }  -> invita y crea el perfil
// POST { accion: "reenviar", id }                         -> reenvía la invitación pendiente
//
// El correo lo envía Supabase Auth (en local, al buzón de pruebas; en producción, por Brevo).
// SITIO_URL: dirección de la aplicación a la que lleva el enlace de la invitación.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const URL_SUPABASE = Deno.env.get("SUPABASE_URL")!;
const CLAVE_SERVICIO = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SITIO = Deno.env.get("SITIO_URL") ?? "http://127.0.0.1:5173";
const ROLES = ["administrador", "direccion", "coordinacion"];
const ETAPAS = ["infantil", "primaria", "pai", "bachillerato"];

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function respuesta(estado: number, cuerpo: Record<string, unknown>) {
  return new Response(JSON.stringify(cuerpo), { status: estado, headers: { ...cors, "Content-Type": "application/json" } });
}

function nivelAcceso(jwt: string): string | null {
  try {
    const b64 = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(b64.padEnd(Math.ceil(b64.length / 4) * 4, "="))).aal ?? null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return respuesta(405, { error: "Método no permitido" });

  const admin = createClient(URL_SUPABASE, CLAVE_SERVICIO, { auth: { persistSession: false, autoRefreshToken: false } });
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: sesion, error: errorSesion } = await admin.auth.getUser(jwt);
  if (errorSesion || !sesion.user) return respuesta(401, { error: "Sin sesión" });

  const { data: yo } = await admin.from("usuario_perfil").select("rol, activo").eq("id", sesion.user.id).maybeSingle();
  if (!yo?.activo || yo.rol !== "administrador") return respuesta(403, { error: "Solo para administradores" });
  // Doble factor obligatorio salvo que la base de datos local lo tenga desactivado (desarrollo).
  const { data: mfa } = await admin.rpc("mfa_admin_obligatorio");
  if (mfa !== false && nivelAcceso(jwt) !== "aal2") return respuesta(403, { error: "Doble factor obligatorio para administradores" });

  let cuerpo: Record<string, unknown>;
  try {
    cuerpo = await req.json();
  } catch {
    return respuesta(400, { error: "Petición no válida" });
  }

  if (cuerpo.accion === "invitar") {
    const nombre = String(cuerpo.nombre ?? "").trim();
    const correo = String(cuerpo.correo ?? "").trim().toLowerCase();
    const rol = String(cuerpo.rol ?? "");
    const etapa = cuerpo.etapa ? String(cuerpo.etapa) : null;
    if (!nombre || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(correo)) return respuesta(400, { error: "Nombre y correo válidos, por favor" });
    if (!ROLES.includes(rol)) return respuesta(400, { error: "Rol no válido" });
    if ((rol === "coordinacion") !== (etapa !== null) || (etapa && !ETAPAS.includes(etapa))) {
      return respuesta(400, { error: "La coordinación necesita etapa, y los demás roles no la llevan" });
    }

    // Antes de invitar: si el correo ya existe, no se invita (Supabase reenviaría al usuario
    // existente) y, sobre todo, no se deshace nada que no se haya creado en esta llamada.
    const { data: existente } = await admin.rpc("admin_id_por_correo", { p_correo: correo });
    if (existente) return respuesta(409, { error: "Ya existe un usuario con ese correo" });

    const { data, error } = await admin.auth.admin.inviteUserByEmail(correo, { redirectTo: SITIO, data: { nombre } });
    if (error || !data.user) {
      const existe = /already|registered|exists/i.test(error?.message ?? "");
      return respuesta(existe ? 409 : 400, { error: existe ? "Ya existe un usuario con ese correo" : "No se ha podido enviar la invitación" });
    }
    const { error: errorPerfil } = await admin.rpc("admin_registrar_invitacion", {
      p_admin: sesion.user.id, p_usuario: data.user.id, p_nombre: nombre, p_rol: rol, p_etapa: etapa, p_reenvio: false,
    });
    if (errorPerfil) {
      // Sin perfil no se deja un usuario suelto: se deshace la invitación. El usuario se acaba
      // de crear en esta llamada (se ha comprobado arriba que el correo no existía).
      await admin.auth.admin.deleteUser(data.user.id);
      return respuesta(400, { error: "No se ha podido crear el perfil" });
    }
    return respuesta(200, { id: data.user.id });
  }

  if (cuerpo.accion === "reenviar") {
    const id = String(cuerpo.id ?? "");
    const { data: u, error } = await admin.auth.admin.getUserById(id);
    if (error || !u.user?.email) return respuesta(404, { error: "Usuario no encontrado" });
    if (u.user.last_sign_in_at) return respuesta(409, { error: "Esta persona ya ha entrado: no necesita invitación" });
    const { data: perfil } = await admin.from("usuario_perfil").select("nombre, rol, etapa, activo").eq("id", id).maybeSingle();
    if (!perfil?.activo) return respuesta(409, { error: "El usuario está desactivado" });
    const { error: errorInv } = await admin.auth.admin.inviteUserByEmail(u.user.email, { redirectTo: SITIO, data: { nombre: perfil.nombre } });
    if (errorInv) return respuesta(400, { error: "No se ha podido reenviar la invitación" });
    await admin.rpc("admin_registrar_invitacion", {
      p_admin: sesion.user.id, p_usuario: id, p_nombre: perfil.nombre, p_rol: perfil.rol, p_etapa: perfil.etapa, p_reenvio: true,
    });
    return respuesta(200, { id });
  }

  return respuesta(400, { error: "Acción no válida" });
});
