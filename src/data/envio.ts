// Envío de informes (§7.10 y §7.14). Solo administración: se elige el tipo de informe (por defecto, a todos sus
// destinatarios), vista previa con los avisos, creación del envío (el servidor recalcula los destinatarios y crea un
// enlace personal por informe, menos los que se quitan) y envío de los correos por la Edge Function enviar-informes, que
// es la única que ve los tokens. En modo «pruebas», todo va a un correo de prueba. La página del enlace (sin cuenta) usa
// informeEnlace y descargaEnlace.

import { FunctionsHttpError } from "@supabase/supabase-js";
import { CURSO, supabase } from "./cliente";
import type { InformeEquipo, InformeJefe, InformeProfesor } from "./resultados";
import type { InformeServicio, InformeTutoria } from "./tutoriaServicios";
import { textosConMayuscula } from "../formato";
import type { SelloDescarga } from "../exportacion/modelo";

export type TipoInforme = "profesor" | "jefatura_departamento" | "jefatura_equipo" | "tutoria" | "servicio";
export const TIPOS_INFORME: TipoInforme[] = ["profesor", "jefatura_departamento", "jefatura_equipo", "tutoria", "servicio"];
export type TipoFiltro = "docente" | "departamento" | "etapa" | "tramo" | "persona" | "grupo" | "servicio";
/** Por cuáles se puede acotar cada informe (sin acotar: todos sus destinatarios). El servidor comprueba lo mismo. */
export const FILTROS: Record<TipoInforme, TipoFiltro[]> = {
  profesor: ["docente", "departamento", "etapa", "tramo"],
  jefatura_departamento: ["persona"],
  jefatura_equipo: ["persona", "tramo"],
  tutoria: ["etapa", "grupo", "persona"],
  servicio: ["servicio"],
};
export interface Seleccion { informe: TipoInforme; filtro: { tipo: "todos" } | { tipo: TipoFiltro; valores: string[] } }

export type Aviso = "sin_destinatario" | "sin_resultados" | "sin_correo";

export interface Destinatario {
  /** Identifica el informe: para quitarlo del envío y para comprobar qué vería su destinatario. */
  clave: string;
  /** Sin destinatario (grupo sin tutor/a, servicio sin responsable): null. */
  persona_id: number | null; tipo: TipoInforme; tramo: string | null; grupo_id: number | null; servicio_id: number | null;
  /** Jefatura de departamento: sus departamentos; del equipo: su tramo; tutoría: el grupo; servicio: su nombre. */
  informe: string | null;
  nombre: string | null; apellidos: string | null; departamento: string | null; correo: string | null;
  destinatario: string | null;
  /** Se queda fuera. */
  aviso: Aviso | null;
  /** Último enlace enviado (y no anulado) de este informe, en el mismo modo. */
  ya_enviado: string | null;
}

export interface VistaPrevia { modo: "pruebas" | "activo"; dias: number; destinatarios: Destinatario[] }

export async function vistaPrevia(seleccion: Seleccion, correoPrueba: string): Promise<VistaPrevia> {
  const { data, error } = await supabase.rpc("admin_envio_destinatarios", { p_curso: CURSO, p_seleccion: seleccion, p_correo_prueba: correoPrueba || null });
  if (error) throw error;
  return data as VistaPrevia;
}

/** ¿Tendría cada destinatario algún resultado visible en su versión? Por tandas (el informe del profesor/a tarda). */
export async function visibles(claves: string[]): Promise<Record<string, boolean>> {
  const { data, error } = await supabase.rpc("admin_envio_visibles", { p_curso: CURSO, p_claves: claves });
  if (error) throw error;
  return (data ?? {}) as Record<string, boolean>;
}

/** Crea los enlaces (menos los que se quitan) y manda los correos. Devuelve cuántos han salido y cuántos han fallado. */
export async function enviar(seleccion: Seleccion, correoPrueba: string, excluir: string[] = []): Promise<{ enlaces: number; enviados: number; errores: number }> {
  const { data, error } = await supabase.rpc("admin_envio_crear", {
    p_curso: CURSO, p_seleccion: seleccion, p_correo_prueba: correoPrueba || null, p_excluir: excluir,
  });
  if (error) throw error;
  const creado = data as { envio: string; enlaces: number };
  const r = await supabase.functions.invoke("enviar-informes", { body: { envio: creado.envio } });
  if (r.error) {
    const detalle = r.error instanceof FunctionsHttpError ? await r.error.context.json().catch(() => ({})) : {};
    throw new Error(detalle.error ?? "No se ha podido contactar con el servidor de correo");
  }
  return { enlaces: creado.enlaces, ...(r.data as { enviados: number; errores: number }) };
}

export interface Jefatura { id: number; nombre: string; apellidos: string; departamentos: string[]; tramos: string[] }

export async function jefaturas(): Promise<Jefatura[]> {
  const { data, error } = await supabase.rpc("admin_jefaturas", { p_curso: CURSO });
  if (error) throw error;
  return (data ?? []) as Jefatura[];
}

export interface EnlaceEnviado {
  id: string; docente: string; tipo: TipoInforme; tramo: string | null; grupo: string | null; servicio: string | null;
  destinatario: string; prueba: boolean; creado: string; enviado: string | null; error: string | null;
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

type Persona = { nombre: string; apellidos: string; departamento: string | null };
export type InformeEnlace =
  | { estado: "caducado"; caduca: string }
  | { estado: "no_valido" }
  | { estado: "limitado" }
  | { estado: "ok"; caduca: string; curso: string; tipo: "profesor"; profesor: Persona; informe: InformeProfesor }
  | { estado: "ok"; caduca: string; curso: string; tipo: "jefatura_departamento"; profesor: Persona; informe: InformeJefe }
  | { estado: "ok"; caduca: string; curso: string; tipo: "jefatura_equipo"; profesor: Persona; informe: InformeEquipo }
  | { estado: "ok"; caduca: string; curso: string; tipo: "tutoria"; profesor: Persona; informe: InformeTutoria }
  | { estado: "ok"; caduca: string; curso: string; tipo: "servicio"; profesor: Persona; informe: InformeServicio };

export async function informeEnlace(token: string): Promise<InformeEnlace> {
  const { data, error } = await supabase.rpc("informe_enlace", { p_token: token });
  if (error) throw error;
  const d = data as InformeEnlace;
  return d.estado === "ok" ? ({ ...d, informe: textosConMayuscula(d.informe) } as InformeEnlace) : d;
}

export async function descargaEnlace(token: string, archivo: string): Promise<SelloDescarga> {
  const { data, error } = await supabase.rpc("descarga_enlace", { p_token: token, p_archivo: archivo });
  if (error) throw error;
  if (!data?.codigo) throw new Error(String(data?.estado ?? "no_valido"));
  return { codigo: data.codigo, nombre: data.nombre, fecha: new Date(data.fecha) };
}
