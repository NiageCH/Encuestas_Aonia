// Informes de tutoría y de servicios (§7.12 y §7.13). Solo Dirección y administración en la aplicación; el tutor/a y el
// responsable de cada servicio los reciben por su enlace personal (§7.10). Las dos versiones de siempre: «completa»,
// con lo que tiene menos de 5 marcado, y la del destinatario («tutor» o «responsable»), con el mínimo de 5 y la
// supresión complementaria, que aplica el servidor.

import { CURSO, supabase } from "./cliente";
import type { Fila } from "./resultados";
import { textosConMayuscula } from "../formato";

type Persona = { id: number; nombre: string; apellidos: string };

export type VersionTutoria = "completa" | "tutor";
export type VersionServicio = "completa" | "responsable";

export interface GrupoTutoria {
  id: number; nombre: string; etapa: string; nivel: string; con_respuestas: boolean; tutor: Persona | null;
}

export interface PreguntaTutoria { codigo: string; texto: string; grupo: Fila; etapa: Fila }
export interface ReferenciaTutoria { codigo: string; texto: string; colectivo: "familias" | "personal"; total: Fila }

export interface InformeTutoria {
  grupo: { id: number; nombre: string; etapa: string; cuestionario: string | null };
  tutor: Persona | null;
  preguntas: PreguntaTutoria[];
  colegio: ReferenciaTutoria[];
  version: VersionTutoria;
}

export interface Servicio {
  id: number; codigo: string; nombre: string; colectivos: string[];
  responsable: (Persona & { correo?: string }) | null;
}

export interface PreguntaServicio { codigo: string; texto: string; principal: boolean; total: Fila; etapas: Fila[] }
export interface ColectivoServicio { colectivo: "alumnos" | "familias" | "personal"; preguntas: PreguntaServicio[]; servicios: Fila | null }

export interface InformeServicio {
  servicio: { id: number; codigo: string; nombre: string };
  responsable: Persona | null;
  colectivos: ColectivoServicio[];
  version: VersionServicio;
}

export async function listarTutorias(): Promise<GrupoTutoria[]> {
  const { data, error } = await supabase.rpc("listar_tutorias", { p_curso: CURSO });
  if (error) throw error;
  return (data ?? []) as GrupoTutoria[];
}

export async function informeTutoria(grupo: number, registrar = false, version: VersionTutoria = "completa"): Promise<InformeTutoria> {
  const { data, error } = await supabase.rpc("informe_tutoria", { p_curso: CURSO, p_grupo: grupo, p_registrar: registrar, p_version: version });
  if (error) throw error;
  return textosConMayuscula(data as InformeTutoria);
}

export async function listarServicios(): Promise<Servicio[]> {
  const { data, error } = await supabase.rpc("listar_servicios", { p_curso: CURSO });
  if (error) throw error;
  return (data ?? []) as Servicio[];
}

export async function informeServicio(servicio: number, registrar = false, version: VersionServicio = "completa"): Promise<InformeServicio> {
  const { data, error } = await supabase.rpc("informe_servicio", { p_curso: CURSO, p_servicio: servicio, p_registrar: registrar, p_version: version });
  if (error) throw error;
  return textosConMayuscula(data as InformeServicio);
}

/** Pone (o cambia) el responsable de un servicio. Solo administración. Si el correo no es de nadie, se crea la persona. */
export async function ponerResponsable(servicio: number, persona: { nombre: string; apellidos: string; correo: string }): Promise<void> {
  const { error } = await supabase.rpc("admin_servicio_responsable", {
    p_curso: CURSO, p_servicio: servicio, p_nombre: persona.nombre, p_apellidos: persona.apellidos, p_correo: persona.correo,
  });
  if (error) throw error;
}

export async function quitarResponsable(servicio: number): Promise<void> {
  const { error } = await supabase.rpc("admin_servicio_responsable_quitar", { p_curso: CURSO, p_servicio: servicio });
  if (error) throw error;
}
