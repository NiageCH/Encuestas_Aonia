// Administración de usuarios (§7.5). Solo administradores con doble factor: lo comprueban las
// RPC y la Edge Function, no solo la interfaz.

import { FunctionsHttpError } from "@supabase/supabase-js";
import { supabase } from "./cliente";
import type { Rol } from "./sesion";

export interface Usuario {
  id: string;
  nombre: string;
  correo: string;
  rol: Rol;
  etapa: string | null;
  estado: "activo" | "pendiente" | "desactivado";
  invitado: string;
  ultimo_acceso: string | null;
  aviso_90_dias: boolean;
  doble_factor: boolean;
}

export interface EntradaRegistro {
  fecha: string;
  accion: string;
  usuario: string;
  /** Quien actuó ya no existe: se muestra con el nombre que tenía al eliminarlo. */
  usuario_eliminado?: boolean;
  detalle: Record<string, unknown>;
}

export async function usuarios(): Promise<Usuario[]> {
  const { data, error } = await supabase.rpc("admin_usuarios");
  if (error) throw error;
  return data as Usuario[];
}

export async function actualizarUsuario(id: string, rol: Rol, etapa: string | null, activo: boolean): Promise<void> {
  const { error } = await supabase.rpc("admin_actualizar_usuario", { p_id: id, p_rol: rol, p_etapa: etapa, p_activo: activo });
  if (error) throw new Error(error.message);
}

/** Elimina la cuenta (perfil, doble factor, sesiones e invitación pendiente). El servidor exige el correo exacto y
 *  no deja eliminarse a uno mismo ni al último administrador; el registro de actividad conserva su historial. */
export async function eliminarUsuario(id: string, correo: string): Promise<void> {
  const { error } = await supabase.rpc("admin_eliminar_usuario", { p_id: id, p_correo: correo });
  if (error) throw new Error(error.message);
}

export async function registro(limite = 200): Promise<EntradaRegistro[]> {
  const { data, error } = await supabase.rpc("admin_registro", { p_limite: limite });
  if (error) throw error;
  return data as EntradaRegistro[];
}

async function funcion(cuerpo: Record<string, unknown>): Promise<void> {
  const { error } = await supabase.functions.invoke("admin-usuarios", { body: cuerpo });
  if (error) {
    if (error instanceof FunctionsHttpError) {
      const respuesta = await error.context.json().catch(() => ({}));
      throw new Error(respuesta.error ?? "Error");
    }
    throw new Error("No se ha podido contactar con el servidor");
  }
}

export const invitar = (nombre: string, correo: string, rol: Rol, etapa: string | null) =>
  funcion({ accion: "invitar", nombre, correo, rol, etapa });

export const reenviarInvitacion = (id: string) => funcion({ accion: "reenviar", id });
