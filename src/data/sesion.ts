// Sesión y perfil del usuario.

import type { Session } from "@supabase/supabase-js";
import { supabase } from "./cliente";
import { sesionRechazada } from "../acceso";

export type Rol = "administrador" | "direccion" | "coordinacion";

export interface Perfil {
  id: string;
  nombre: string;
  rol: Rol;
  etapa: string | null;
  activo: boolean;
}

export async function entrar(correo: string, contrasena: string): Promise<void> {
  const { error } = await supabase.auth.signInWithPassword({ email: correo, password: contrasena });
  if (error) throw error;
  guardarVersion();
}

export async function salir(): Promise<void> {
  await supabase.auth.signOut();
}

/**
 * Sesión guardada en el navegador, validada con el servidor antes de pedir datos. Si el servidor no la reconoce
 * (caducada, revocada, usuario desactivado o de otro proyecto), se borra y se vuelve a la pantalla de acceso.
 * Un fallo de red no cierra la sesión: la pantalla mostrará el error y se podrá reintentar.
 */
export function sesionActual(): Promise<Session | null> {
  validacion ??= validarSesionGuardada().finally(() => { validada = true; });
  return validacion;
}

// Mientras se valida la sesión guardada, los avisos de Supabase se ignoran: al recuperarla emite la sesión guardada
// (como inicial y como «iniciada») y, si se usara, se pedirían datos antes de comprobarla con el servidor.
const CLAVE_VERSION = "encuestas.version_web";
let validacion: Promise<Session | null> | null = null;
let validada = false;
const VERSION_AL_ABRIR = versionGuardada();

async function validarSesionGuardada(): Promise<Session | null> {
  const { data } = await supabase.auth.getSession();
  if (!data.session) return null;
  let sesion = data.session;
  // Sesión guardada con otra versión de la web: se renueva con el servidor (token y nivel de acceso nuevos) antes de
  // pedir datos. Si el servidor la rechaza, se borra.
  if (VERSION_AL_ABRIR !== __VERSION_WEB__) {
    const { data: renovada, error } = await supabase.auth.refreshSession();
    if (error && sesionRechazada(error)) return cerrarLocal();
    if (renovada.session) sesion = renovada.session;
  }
  const { error } = await supabase.auth.getUser();
  if (error && sesionRechazada(error)) return cerrarLocal();
  guardarVersion();
  return sesion;
}

async function cerrarLocal(): Promise<null> {
  await supabase.auth.signOut({ scope: "local" });
  return null;
}

// Versión de la web con la que se guardó la sesión. Si el navegador no deja guardar, se valida siempre.
function versionGuardada(): string | null {
  if (typeof localStorage === "undefined") return null;
  try { return localStorage.getItem(CLAVE_VERSION); } catch { return null; }
}
function guardarVersion(): void {
  try { localStorage.setItem(CLAVE_VERSION, __VERSION_WEB__); } catch { /* sin almacenamiento: se valida en cada apertura */ }
}

export function alCambiarSesion(fn: (s: Session | null) => void): () => void {
  // La sesión inicial la da sesionActual(), ya validada.
  const { data } = supabase.auth.onAuthStateChange((evento, s) => {
    if (!validada || evento === "INITIAL_SESSION") return;
    fn(s);
  });
  return () => data.subscription.unsubscribe();
}

/** Perfil propio (la política RLS solo deja leer el propio, o todos si se es administrador). */
export async function miPerfil(id: string): Promise<Perfil | null> {
  const { data, error } = await supabase
    .from("usuario_perfil")
    .select("id, nombre, rol, etapa, activo")
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  return data as Perfil | null;
}

/** Correo para elegir una contraseña nueva. No dice si el correo existe. */
export async function pedirRecuperacion(correo: string): Promise<void> {
  await supabase.auth.resetPasswordForEmail(correo, { redirectTo: `${window.location.origin}/` });
}

/** Contraseña nueva (al aceptar la invitación o al recuperar la contraseña). */
export async function cambiarContrasena(contrasena: string): Promise<void> {
  const { error } = await supabase.auth.updateUser({ password: contrasena });
  if (error) throw error;
}

// Doble factor (TOTP) de los administradores ------------------------------------------------

export interface FactorTotp { id: string; verificado: boolean }

export async function factoresTotp(): Promise<FactorTotp[]> {
  const { data, error } = await supabase.auth.mfa.listFactors();
  if (error) throw error;
  return data.all.filter((f) => f.factor_type === "totp").map((f) => ({ id: f.id, verificado: f.status === "verified" }));
}

/** Alta de un factor nuevo: devuelve el QR (SVG en data URL) y el secreto para escribirlo a mano.
 *  Si se pide dos veces a la vez (React lo hace en desarrollo), se reutiliza la misma alta:
 *  dos altas simultáneas dejaban dos factores y un QR que no correspondía. */
let altaEnCurso: Promise<{ id: string; qr: string; secreto: string }> | null = null;

export function altaTotp(): Promise<{ id: string; qr: string; secreto: string }> {
  altaEnCurso ??= nuevaAltaTotp().finally(() => { setTimeout(() => { altaEnCurso = null; }, 1000); });
  return altaEnCurso;
}

async function nuevaAltaTotp(): Promise<{ id: string; qr: string; secreto: string }> {
  // Un alta a medias (sin verificar) impide empezar otra: se quita antes.
  for (const f of await factoresTotp()) {
    if (!f.verificado) await supabase.auth.mfa.unenroll({ factorId: f.id });
  }
  const { data, error } = await supabase.auth.mfa.enroll({ factorType: "totp", friendlyName: `Encuestas ${new Date().toISOString()}` });
  if (error) throw error;
  if (data.type !== "totp") throw new Error("Factor inesperado");
  return { id: data.id, qr: data.totp.qr_code, secreto: data.totp.secret };
}

export async function verificarTotp(factorId: string, codigo: string): Promise<void> {
  const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId, code: codigo.replace(/\s+/g, "") });
  if (error) throw error;
}

/** ¿Doble factor obligatorio para administradores? Siempre sí, salvo que la base de datos local
 *  lo tenga desactivado para desarrollo. Ante cualquier duda, se considera obligatorio. */
export async function mfaAdminObligatorio(): Promise<boolean> {
  const { data, error } = await supabase.rpc("mfa_admin_obligatorio");
  return error ? true : data !== false;
}
