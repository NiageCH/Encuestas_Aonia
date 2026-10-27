// Exportación de una vista (§7.6): tablas con lo mismo que se ve en pantalla, sacado de las mismas
// RPC (permisos, mínimo de 5 y supresión complementaria ya aplicados). De este modelo salen el CSV
// y el PDF, así que los dos dicen exactamente lo mismo.

import type { Fila } from "../data/resultados";
import { t } from "../i18n";

/** Una celda: texto, enunciado de una pregunta u opción (tal como está guardado: el CSV lo copia igual y el PDF le pone
 *  mayúscula inicial), número (con sus decimales) o resultado oculto. Nunca hay celdas en blanco. */
export type Valor = { texto: string } | { enunciado: string } | { num: number; dec: number } | { oculto: string };

export interface Tabla {
  titulo: string;
  columnas: string[];
  filas: Valor[][];
  notas?: string[];
}

export type VistaExportable = "inicio" | "alumnos" | "familias" | "personal" | "descargas";

/** Quién descargó, cuándo y con qué código: lo pone el servidor (registrar_descarga) y va en el pie de cada página del PDF
 *  y en la cabecera del CSV. */
export interface SelloDescarga { codigo: string; nombre: string; fecha: Date }

export interface Exportacion {
  vista: VistaExportable;
  /** Nombre de la vista en la cabecera: «Familias». */
  titulo: string;
  /** Filtros activos, en el orden de la pantalla: [["Etapa", "PAI"]]. */
  filtros: [string, string][];
  /** Partes del nombre de archivo tras «Encuestas_2526_»: ["Familias", "Etapa-PAI"]. */
  archivo: string[];
  tablas: Tabla[];
  /** Notas generales al final (anonimato, cierre). */
  notas: string[];
  /** Sin la línea del curso (el registro de descargas no es de un curso). */
  sinCurso?: boolean;
}

export const txt = (texto: string): Valor => ({ texto });
export const enunciado = (texto: string): Valor => ({ enunciado: texto });
export const num = (x: number, dec = 0): Valor => ({ num: x, dec });

/** Texto de una celda oculta, el mismo que en pantalla. */
export function textoOculto(fila: Pick<Fila, "motivo">): string {
  return fila.motivo === "menos_de_5" ? t.oculto_menos5 : fila.motivo === "sin_datos" ? t.sin_datos : t.oculto_compl;
}

export type Campo =
  | "n" | "personas" | "valoraciones" | "media" | "nsnc"
  | "rec_media" | "si" | "neutral" | "no" | "indice"
  | "d1" | "d2" | "d3" | "d4" | "d5" | "d6";

/** Las celdas de una fila de resultados. Si está oculta, cada celda dice por qué. */
export function celdas(fila: Fila, campos: Campo[]): Valor[] {
  if (fila.suprimido) return campos.map(() => ({ oculto: textoOculto(fila) }));
  return campos.map((c): Valor => {
    switch (c) {
      case "n": return num(fila.n ?? 0);
      case "personas": return num(fila.n_personas ?? fila.n ?? 0);
      case "valoraciones": return num(fila.n_valoraciones ?? fila.n ?? 0);
      case "media": return num(fila.media ?? 0, 2);
      case "nsnc": return num(fila.ns_nc ?? 0);
      case "rec_media": return num(fila.media ?? 0, 1);
      case "si": return num(fila.promotores_pct ?? 0);
      case "neutral": return num(fila.neutros_pct ?? 0);
      case "no": return num(fila.detractores_pct ?? 0);
      case "indice": return num(fila.nps ?? 0);
      default: return num(fila.distribucion?.[c.slice(1)] ?? 0);
    }
  });
}

/** Notas comunes a todas las exportaciones. */
export function notasComunes(): string[] {
  return [t.leyenda_oculto, t.aviso_cierre];
}

// Tablas que se repiten en varias vistas ------------------------------------------------------

export const COLUMNAS_REC = [t.exp_col_quien, t.exp_col_escala, t.exp_col_personas, t.exp_col_media_rec,
  t.exp_col_si, t.exp_col_neutral, t.exp_col_no, t.indice];

export function filaRecomendacion(etiqueta: string, escala: string, fila: Fila): Valor[] {
  return [txt(etiqueta), txt(t.escala_de(escala)), ...celdas(fila, ["n", "rec_media", "si", "neutral", "no", "indice"])];
}

export function tablaRecomendacion(titulo: string, etiqueta: string, escala: string, fila: Fila): Tabla {
  return { titulo, columnas: COLUMNAS_REC, filas: [filaRecomendacion(etiqueta, escala, fila)], notas: [t.calculo_reparto, t.calculo_indice] };
}

/** Cuántas personas dan cada puntuación de la recomendación. */
export function tablaDistribucion(fila: Fila, desde: number): Tabla {
  const titulo = t.distribucion;
  const columnas = [t.exp_col_puntuacion, t.exp_col_personas, t.exp_col_porcentaje];
  if (fila.suprimido) return { titulo, columnas, filas: [[txt(t.exp_todas), ...celdas(fila, ["n", "n"])]] };
  const n = fila.n ?? 0;
  const filas: Valor[][] = [];
  for (let v = desde; v <= 10; v++) {
    const c = fila.distribucion?.[String(v)] ?? 0;
    filas.push([num(v), num(c), num(n ? (100 * c) / n : 0)]);
  }
  return { titulo, columnas, filas };
}

/** Media de un bloque o de una parte (asignatura, etapa, departamento...). */
export function tablaMedias(titulo: string, columnaEtiqueta: string, filas: { etiqueta: string; fila: Fila }[], notas?: string[]): Tabla {
  return {
    titulo, notas,
    columnas: [columnaEtiqueta, t.exp_col_personas, t.exp_col_valoraciones, t.exp_col_media],
    filas: filas.map(({ etiqueta, fila }) => [txt(etiqueta), ...celdas(fila, ["personas", "valoraciones", "media"])]),
  };
}

/** Detalle por pregunta de un bloque: valoraciones, media y cuántas personas dan cada puntuación. */
export function tablaDetalle(bloque: string, preguntas: { texto: string; fila: Fila }[], etiquetas: string[]): Tabla {
  return {
    titulo: `${t.detalle}: ${bloque}`,
    columnas: [t.exp_col_pregunta, t.exp_col_valoraciones, t.exp_col_media, "1", "2", "3", "4", "5", "6", t.exp_col_nsnc],
    filas: preguntas.map(({ texto, fila }) => [enunciado(texto), ...celdas(fila, ["n", "media", "d1", "d2", "d3", "d4", "d5", "d6", "nsnc"])]),
    notas: [t.exp_nota_detalle(etiquetas.map((e, i) => `${i + 1} ${e}`).join(" · "))],
  };
}

/** Aspectos más destacados: porcentaje de personas que eligen cada aspecto. */
export function tablaValorado(titulo: string, fila: Fila, textos: Record<string, string>): Tabla {
  const columnas = [t.exp_col_aspecto, t.exp_col_personas, t.exp_col_porcentaje];
  if (fila.suprimido) return { titulo, columnas, filas: [[txt(t.exp_todos_aspectos), ...celdas(fila, ["n", "n"])]] };
  const ops = [...(fila.opciones ?? [])].filter((o) => o.n > 0).sort((a, b) => b.n - a.n);
  return {
    titulo, columnas,
    filas: ops.map((o) => [enunciado(textos[o.codigo] ?? o.codigo), num(o.n), num(o.pct)]),
    notas: [t.exp_nota_valorado(fila.n ?? 0)],
  };
}
