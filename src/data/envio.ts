// Envío de informes al profesorado (§7.10). Solo administración: vista previa de destinatarios, creación del envío
// (el servidor recalcula los destinatarios y crea un enlace personal por docente) y envío de los correos por la Edge
// Function enviar-informes, que es la única que ve los tokens. En modo «pruebas», todo va a un correo de Niage.
// La página del enlace (sin cuenta) usa informeEnlace y descargaEnlace.

import { FunctionsHttpError } from "@supabase/supabase-js";
import { CURSO, supabase } from "./cliente";
import type { InformeProfesor } from "./resultados";
import { textosConMayuscula } from "../formato";
import type { SelloDescarga } from "../exportacion/modelo";

export type TipoSeleccion = "docente" | "departamento" | "etapa" | "tramo" | "todos";
export interface Seleccion { tipo: TipoSeleccion; valores?: string[] }

export interface Destinatario {
  docente_id: number; nombre: string; apellidos: string; departamento: string | null; correo: string | null;
  destinatario: string;
  /** Se queda fuera: sin resultados del alumnado o sin correo. */
  aviso: "sin_resultados" | "sin_correo" | null;
}

export interface VistaPrevia { modo: "pruebas" | "activo"; dias: number; destinatarios: Destinatario[] }

export async function vistaPrevia(seleccion: Seleccion, correoPrueba: string): Promise<VistaPrevia> {
  const { data, error } = await supabase.rpc("admin_envio_destinatarios", { p_curso: CURSO, p_seleccion: seleccion, p_correo_prueba: correoPrueba || null });
  if (error) throw error;
  return data as VistaPrevia;
}

/** Crea los enlaces y manda los correos. Devuelve cuántos han salido y cuántos han fallado. */
export async function enviar(seleccion: Seleccion, correoPrueba: string): Promise<{ enlaces: number; enviados: number; errores: number }> {
  const { data, error } = await supabase.rpc("admin_envio_crear", { p_curso: CURSO, p_seleccion: seleccion, p_correo_prueba: correoPrueba || null });
  if (error) throw error;
  const creado = data as { envio: string; enlaces: number };
  const r = await supabase.functions.invoke("enviar-informes", { body: { envio: creado.envio } });
  if (r.error) {
    const detalle = r.error instanceof FunctionsHttpError ? await r.error.context.json().catch(() => ({})) : {};
    throw new Error(detalle.error ?? "No se ha podido contactar con el servidor de correo");
  }
  return { enlaces: creado.enlaces, ...(r.data as { enviados: number; errores: number }) };
}

export interface EnlaceEnviado {
  id: string; docente: string; destinatario: string; prueba: boolean; creado: string; enviado: string | null; error: string | null;
  caduca: string; anulado: string | null; pendiente: boolean; aperturas: number; descargas: number; ultima: string | null;
}

export async function enviados(): Promise<EnlaceEnviado[]> {
  const { data, error } = await supabase.rpc("admin_envios", { p_curso: CURSO });
  if (error) throw error;
  return (data ?? []) as EnlaceEnviado[];
}

export async function anularEnlace(id: string): Promise<void> {
  const { error } = await supabase.rpc("admin_enlace_anular", { p_enlace: id });
  if (error) throw error;
}

// Página del enlace (sin cuenta) ---------------------------------------------------------------------------------------

export type InformeEnlace =
  | { estado: "caducado"; caduca: string }
  | { estado: "ok"; caduca: string; curso: string; profesor: { nombre: string; apellidos: string; departamento: string | null }; informe: InformeProfesor };

export async function informeEnlace(token: string): Promise<InformeEnlace> {
  const { data, error } = await supabase.rpc("informe_enlace", { p_token: token });
  if (error) throw error;
  const d = data as InformeEnlace;
  return d.estado === "ok" ? { ...d, informe: textosConMayuscula(d.informe) } : d;
}

export async function descargaEnlace(token: string, archivo: string): Promise<SelloDescarga> {
  const { data, error } = await supabase.rpc("descarga_enlace", { p_token: token, p_archivo: archivo });
  if (error) throw error;
  return { codigo: data.codigo, nombre: data.nombre, fecha: new Date(data.fecha) };
}
