// Edge Function: envío de los informes por correo (§7.10 y §7.14): profesorado, jefaturas, tutoría y servicios. La usa un administrador activo con doble factor (aal2)
// después de crear el envío (admin_envio_crear, con su vista previa). Lee los correos pendientes con la clave de
// servicio (los tokens nunca llegan al navegador), los envía por SMTP y marca cada uno.
//
// POST { envio: "<id>" }  ->  { enviados, errores }
//
// Doble cerrojo para no escribir al profesorado antes de tiempo: la base de datos (modo «pruebas») solo crea enlaces a
// los dos correos de prueba (rodrigo@niage.es y mark.polko@sfpaula.com, desde el 04/11/2026), y aquí se comprueba otra
// vez: cualquier otro destinatario, o un correo que no sea de prueba, exige ENVIO_PROFESORADO=activo y el remitente del
// Colegio (encuestas@sfpaula.com).
//
// Variables (secretos de la función): SMTP_HOST, SMTP_PORT (465 recomendado: Supabase no deja salir por el 25 ni el 587),
// SMTP_USER, SMTP_PASS, REMITENTE, SITIO_URL y, cuando el Colegio lo autorice, ENVIO_PROFESORADO=activo.
// En local, sin SMTP_HOST, va al buzón de pruebas de Supabase (Mailpit, http://127.0.0.1:55424 o el puerto de inbucket).

import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import nodemailer from "npm:nodemailer@6.9.16";

const URL_SUPABASE = Deno.env.get("SUPABASE_URL")!;
const CLAVE_SERVICIO = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const LOCAL = URL_SUPABASE === "http://kong:8000";
const REMITENTE_COLEGIO = "encuestas@sfpaula.com";
const REMITENTE = Deno.env.get("REMITENTE") ?? (LOCAL ? "encuestas@niage.eu" : "");
const ACTIVO = Deno.env.get("ENVIO_PROFESORADO") === "activo" && REMITENTE.toLowerCase() === REMITENTE_COLEGIO;
const CORREOS_PRUEBA = new Set(["rodrigo@niage.es", "mark.polko@sfpaula.com"]);
const dePrueba = (p: { destinatario: string; prueba: boolean }) => p.prueba && CORREOS_PRUEBA.has(p.destinatario.trim().toLowerCase());

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

const fecha = (iso: string) =>
  new Date(iso).toLocaleString("es-ES", { timeZone: "Europe/Madrid", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });

interface Pendiente {
  enlace: string; token: string; destinatario: string; prueba: boolean; caduca: string;
  tipo: "profesor" | "jefatura_departamento" | "jefatura_equipo" | "tutoria" | "servicio"; tramo: string | null;
  grupo: string | null; servicio: string | null;
  nombre: string; apellidos: string; correo_docente: string | null; curso: string; modo: string;
}

const TRAMOS: Record<string, string> = { infantil: "Infantil", y1_y5: "Y1 a Y5", y6_y9: "Y6 a Y9", y10_y12: "Y10 a Y12" };

function correo(p: Pendiente, sitio: string) {
  const enlace = `${sitio.replace(/\/$/, "")}/#/informe/${p.token}`;
  const que = p.tipo === "profesor" ? `su informe de las encuestas de satisfacción del alumnado del curso ${p.curso}, con los resultados de sus clases`
    : p.tipo === "jefatura_departamento" ? `el informe de su jefatura de departamento del curso ${p.curso}, con los resultados de las encuestas de personal`
    : p.tipo === "jefatura_equipo" ? `el informe del Equipo de Individuación (${TRAMOS[p.tramo ?? ""] ?? p.tramo}) del curso ${p.curso}, con los resultados de las encuestas de personal`
    : p.tipo === "tutoria" ? `el informe de tutoría de ${p.grupo} del curso ${p.curso}, con lo que dice el alumnado de su grupo en las encuestas de satisfacción`
    : `el informe del servicio «${p.servicio}» del curso ${p.curso}, con la valoración del alumnado, las familias y el personal en las encuestas de satisfacción`;
  const titulo = p.tipo === "profesor" ? "Su informe de las encuestas del alumnado"
    : p.tipo === "tutoria" ? `Su informe de tutoría (${p.grupo})`
    : p.tipo === "servicio" ? `Informe del servicio «${p.servicio}»` : "Su informe de jefatura";
  const asunto = `${p.prueba ? "[PRUEBA] " : ""}${titulo} ${p.curso}`;
  const quien = { profesor: "el docente", jefatura_departamento: "la jefatura", jefatura_equipo: "la jefatura", tutoria: "el tutor/a", servicio: "el responsable del servicio" }[p.tipo];
  const prueba = p.prueba
    ? `ESTO ES UNA PRUEBA. Este correo no se ha enviado a ${quien}: iría a ${p.nombre} ${p.apellidos} (${p.correo_docente ?? "sin correo"}).\n\n`
    : "";
  const texto = `${prueba}Hola, ${p.nombre}:

El Colegio le envía ${que}.

Ábralo con este enlace personal:
${enlace}

El enlace es solo para usted y caduca el ${fecha(p.caduca)}. No lo reenvíe. Si caduca, pida uno nuevo a Dirección.

Colegio Internacional de Sevilla, San Francisco de Paula`;
  return { asunto, texto };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return respuesta(405, { error: "Método no permitido" });

  const admin = createClient(URL_SUPABASE, CLAVE_SERVICIO, { auth: { persistSession: false, autoRefreshToken: false } });
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: sesion, error: errorSesion } = await admin.auth.getUser(jwt);
  if (errorSesion || !sesion.user) return respuesta(401, { error: "Sin sesión" });
  const { data: yo } = await admin.from("usuario_perfil").select("rol, activo").eq("id", sesion.user.id).maybeSingle();
  if (!yo?.activo || yo.rol !== "administrador") return respuesta(403, { error: "Solo para administración" });
  const { data: mfa } = await admin.rpc("mfa_admin_obligatorio");
  if (mfa !== false && nivelAcceso(jwt) !== "aal2") return respuesta(403, { error: "Doble factor obligatorio para las cuentas de administración" });

  let envio = "";
  try {
    envio = String((await req.json()).envio ?? "");
  } catch {
    return respuesta(400, { error: "Petición no válida" });
  }
  if (!/^\d+$/.test(envio)) return respuesta(400, { error: "Envío no válido" });

  const sitio = Deno.env.get("SITIO_URL") ?? (LOCAL ? (req.headers.get("origin") ?? "http://127.0.0.1:5173") : "");
  if (!REMITENTE || !sitio) return respuesta(500, { error: "Falta configurar el remitente o la dirección de la web" });
  const host = Deno.env.get("SMTP_HOST") ?? (LOCAL ? "inbucket" : "");
  if (!host) return respuesta(500, { error: "Falta configurar el servidor de correo" });
  const puerto = Number(Deno.env.get("SMTP_PORT") ?? (LOCAL ? "1025" : "465"));
  const transporte = nodemailer.createTransport({
    host, port: puerto, secure: puerto === 465,
    auth: Deno.env.get("SMTP_USER") ? { user: Deno.env.get("SMTP_USER"), pass: Deno.env.get("SMTP_PASS") } : undefined,
  });

  const { data, error } = await admin.rpc("envio_pendientes", { p_envio: envio });
  if (error) return respuesta(400, { error: "No se han podido leer los correos pendientes" });
  let enviados = 0;
  let errores = 0;
  for (const p of (data ?? []) as Pendiente[]) {
    // Segundo cerrojo: fuera de los correos de prueba, solo con el envío activado y el remitente del Colegio.
    if (!dePrueba(p) && !(ACTIVO && p.modo === "activo")) {
      await admin.rpc("envio_marcar", { p_enlace: p.enlace, p_error: "Bloqueado: el envío al profesorado no está activado" });
      errores++;
      continue;
    }
    const { asunto, texto } = correo(p, sitio);
    try {
      await transporte.sendMail({ from: `Encuestas CIS-SFP <${REMITENTE}>`, to: p.destinatario, subject: asunto, text: texto });
      await admin.rpc("envio_marcar", { p_enlace: p.enlace, p_error: null });
      enviados++;
    } catch (e) {
      await admin.rpc("envio_marcar", { p_enlace: p.enlace, p_error: `No se ha podido enviar: ${(e as Error).message}`.slice(0, 300) });
      errores++;
    }
  }
  return respuesta(200, { enviados, errores });
});
