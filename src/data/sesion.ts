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
