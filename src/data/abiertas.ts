// Respuestas abiertas (§7.9): solo Dirección y administración. Cada consulta queda en el registro de actividad (lo anota
// el servidor). Los textos llegan tal cual, sueltos y en orden aleatorio: sin nada que los enlace con las respuestas
// cerradas de la misma persona.

import { CURSO, supabase } from "./cliente";
import type { Colectivo } from "./resultados";

export interface PreguntaAbierta {
  id: number;
  colectivo: Colectivo;
  cuestionario: string;
  cuestionario_titulo: string;
  etapa: string | null;
  /** La misma pregunta en varios cuestionarios: echa_en_falta, comentario... */
  codigo: string;
  texto: string;
  nota: string | null;
  n: number;
}

export async function preguntasAbiertas(): Promise<PreguntaAbierta[]> {
  const { data, error } = await supabase.rpc("abiertas_preguntas", { p_curso: CURSO });
  if (error) throw error;
  return (data ?? []) as PreguntaAbierta[];
}

export interface FiltroAbiertas {
  colectivo: Colectivo;
  pregunta: string;
  etapa?: string;
  cuestionario?: string;
  grupo?: string;
  docente?: boolean;
  antiguedad?: "primer_ano" | "mas_de_un_ano";
}

export interface ResultadoAbiertas {
  preguntas: { cuestionario: string; cuestionario_titulo: string; texto: string; nota: string | null }[];
  n: number;
  respuestas: { texto: string; cuestionario: string }[];
}

/** Las respuestas de una pregunta con los filtros del colectivo. Queda en el registro de actividad. */
export async function respuestasAbiertas(filtro: FiltroAbiertas): Promise<ResultadoAbiertas> {
  const { data, error } = await supabase.rpc("abiertas", { p_filtro: { curso: CURSO, ...filtro } });
  if (error) throw error;
  return data as ResultadoAbiertas;
}

export async function gruposAbiertas(cuestionario: string): Promise<string[]> {
  const { data, error } = await supabase.rpc("abiertas_grupos", { p_curso: CURSO, p_cuestionario: cuestionario });
  if (error) throw error;
  return (data ?? []) as string[];
}
