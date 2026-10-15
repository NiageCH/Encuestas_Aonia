// Sesión y perfil del usuario.

import type { Session } from "@supabase/supabase-js";
import { supabase } from "./cliente";

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
}

export async function salir(): Promise<void> {
  await supabase.auth.signOut();
}

export async function sesionActual(): Promise<Session | null> {
  const { data } = await supabase.auth.getSession();
  return data.session;
}

export function alCambiarSesion(fn: (s: Session | null) => void): () => void {
  const { data } = supabase.auth.onAuthStateChange((_evento, s) => fn(s));
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
