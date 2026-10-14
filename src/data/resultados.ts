// Acceso a los resultados. Todo pasa por las RPC agregadas: el cliente nunca ve respuestas
// individuales, y lo que llega ya trae aplicados permisos, mínimo de 5 y supresión
// complementaria.

import { CURSO, supabase } from "./cliente";

export type Motivo = "menos_de_5" | "complementaria" | "sin_datos";

export interface Fila {
  clave: Record<string, string>;
  suprimido: boolean;
  motivo?: Motivo;
  n?: number;
  media?: number;
  n_personas?: number;
  n_valoraciones?: number;
  ns_nc?: number;
  distribucion?: Record<string, number>;
  promotores_pct?: number;
  neutros_pct?: number;
  detractores_pct?: number;
  nps?: number;
  opciones?: { codigo: string; n: number; pct: number }[];
}

export interface Resultado {
  total: Fila;
  partes: Fila[];
  dimensiones: string[];
}

export type Colectivo = "alumnos" | "familias" | "personal";

export interface Filtro {
  colectivo: Colectivo;
  cuestionario?: string;
  etapa?: string;
  grupo?: string;
  asignatura?: string;
  docente?: boolean;
  antiguedad?: "primer_ano" | "mas_de_un_ano";
  idioma?: "es" | "en";
}

export type Metrica =
  | { tipo: "personas" }
  | { tipo: "satisfaccion" }
  | { tipo: "recomendacion" }
  | { tipo: "bloque"; codigo: string }
  | { tipo: "pregunta"; codigo: string }
  | { tipo: "seleccion"; codigo: string };

export async function resultados(filtro: Filtro, metrica: Metrica, dimensiones: string[] = []): Promise<Resultado> {
  const { data, error } = await supabase.rpc("resultados", {
    p_filtro: { curso: CURSO, ...filtro },
    p_metrica: metrica,
    p_dimensiones: dimensiones,
  });
  if (error) throw error;
  return data as Resultado;
}

export interface Cuestionario {
  codigo: string;
  titulo: string;
  etapa: string | null;
  respuestas_incompletas: number;
  idiomas_cargados: string[];
}

export async function cuestionarios(colectivo: Colectivo): Promise<Cuestionario[]> {
  const { data, error } = await supabase
    .from("cuestionario")
    .select("codigo, titulo, etapa, respuestas_incompletas, idiomas_cargados, curso!inner(nombre)")
    .eq("colectivo", colectivo)
    .eq("curso.nombre", CURSO)
    .order("id");
  if (error) throw error;
  return (data ?? []).map(({ codigo, titulo, etapa, respuestas_incompletas, idiomas_cargados }) => ({
    codigo, titulo, etapa, respuestas_incompletas, idiomas_cargados,
  }));
}

export interface Bloque {
  codigo: string;
  nombre: string;
  orden: number;
  entra_en_media: boolean;
}

export async function bloques(cuestionario: string): Promise<Bloque[]> {
  const { data, error } = await supabase
    .from("bloque")
    .select("codigo, nombre, orden, entra_en_media, cuestionario!inner(codigo, curso!inner(nombre))")
    .eq("cuestionario.codigo", cuestionario)
    .eq("cuestionario.curso.nombre", CURSO)
    .order("orden");
  if (error) throw error;
  return (data ?? []).map(({ codigo, nombre, orden, entra_en_media }) => ({ codigo, nombre, orden, entra_en_media }));
}

export interface DetallePregunta {
  codigo: string;
  texto: string;
  resultado: Resultado;
}

/** Cada pregunta de un bloque (por su código), en el orden del cuestionario. */
export async function detallePreguntas(filtro: Filtro, bloque: string, dimensiones: string[] = []): Promise<DetallePregunta[]> {
  const { data, error } = await supabase.rpc("detalle_preguntas", {
    p_filtro: { curso: CURSO, ...filtro },
    p_bloque: bloque,
    p_dimensiones: dimensiones,
  });
  if (error) throw error;
  return data as DetallePregunta[];
}

/** Texto de cada opción de una pregunta de selección múltiple (código -> texto). */
export async function opciones(pregunta: string): Promise<Record<string, string>> {
  const { data, error } = await supabase
    .from("opcion")
    .select("codigo, texto_es, pregunta!inner(codigo_diccionario)")
    .eq("pregunta.codigo_diccionario", pregunta);
  if (error) throw error;
  return Object.fromEntries((data ?? []).map((o) => [o.codigo, o.texto_es]));
}

/** Recuento informativo de personas por idioma en personal (cifras exactas, §5): no existe
 *  ningún resultado desagregado por idioma. */
export async function recuentoIdiomas(): Promise<Record<string, number>> {
  const { data, error } = await supabase.rpc("recuento_idiomas", { p_curso: CURSO });
  if (error) throw error;
  return (data ?? {}) as Record<string, number>;
}
