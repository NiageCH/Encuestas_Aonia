// Tabla «Detalle por pregunta» del informe del profesor/a (§7.2, petición de Mark del 10/11/2026). La misma para la
// pantalla, el PDF (completo y docente) y el enlace personal: qué columnas lleva, qué va en cada celda y qué notas
// hacen falta debajo. No lee respuestas: solo junta las celdas que ya manda el servidor con la versión del rol (la media
// del docente en una etapa sale de sus clases visibles de esa etapa, igual que el servidor calcula su media global).

import type { CeldaProfesor, Fila, InformeProfesor, ResultadoProfesor } from "./resultados";

/** Por qué una celda no lleva cifra. Cada una tiene su nota debajo de la tabla. */
export type NotaTabla =
  | "menos_de_5"        // el resultado tiene menos de 5 respuestas
  | "complementaria"    // se oculta para que no se deduzca otro por resta
  | "sin_datos"         // no hay respuestas
  | "sin_visibles"      // tiene clases propias con la pregunta, pero todas están ocultas
  | "sin_propias"       // sus clases con la pregunta son compartidas: no entran en su media
  | "no_se_pregunta"    // la pregunta no está en el cuestionario de esa etapa
  | "no_se_muestra";    // Colegio en una pregunta de dos etapas, en la versión docente

export type ValorTabla = { media: number; menos_de_5?: boolean } | { nota: NotaTabla };

export type ColumnaTabla =
  | { tipo: "docente" }                         // este profesor/a, todas sus clases propias visibles
  | { tipo: "docente_etapa"; etapa: string }    // este profesor/a en una etapa (solo si tiene varias)
  | { tipo: "etapa"; etapa: string }            // todo el profesorado de la etapa
  | { tipo: "colegio" };                        // todo el profesorado del Colegio

export interface TablaProfesor {
  etapas: string[];
  /** Con dos etapas o más: por cada etapa, su media y la de todo el profesorado, juntas. */
  porPares: boolean;
  columnas: ColumnaTabla[];
  filas: { codigo: string; texto: string; valores: ValorTabla[] }[];
  /** Notas que aparecen en la tabla, en orden fijo. */
  notas: NotaTabla[];
}

const ORDEN_NOTAS: NotaTabla[] = ["menos_de_5", "complementaria", "sin_datos", "sin_visibles", "sin_propias", "no_se_pregunta", "no_se_muestra"];
const ORDEN_ETAPAS = ["infantil", "primaria", "pai", "bachillerato"];

export const etapasDelInforme = (informe: Pick<ResultadoProfesor, "comparacion">) =>
  Object.keys(informe.comparacion).filter((k) => k !== "colegio")
    .sort((a, b) => ORDEN_ETAPAS.indexOf(a) - ORDEN_ETAPAS.indexOf(b));

/** Nota de un resultado oculto por el servidor. */
export const notaDeFila = (fila: Pick<Fila, "motivo">): NotaTabla =>
  fila.motivo === "menos_de_5" ? "menos_de_5" : fila.motivo === "sin_datos" ? "sin_datos" : "complementaria";

const deFila = (fila: Fila): ValorTabla =>
  fila.suprimido ? { nota: notaDeFila(fila) } : { media: fila.media!, menos_de_5: fila.menos_de_5 };

/** Media del docente con unas celdas: solo sus clases propias o atribuidas visibles, ponderada por valoraciones. */
export function mediaDocente(celdas: CeldaProfesor[]): ValorTabla {
  if (celdas.length === 0) return { nota: "no_se_pregunta" };
  const propias = celdas.filter((c) => c.tipo !== "compartida");
  if (propias.length === 0) return { nota: "sin_propias" };
  const visibles = propias.filter((c) => !c.suprimido && c.media != null);
  let suma = 0, n = 0;
  for (const c of visibles) {
    const v = c.n_valoraciones ?? 0;
    suma += c.media! * v; n += v;
  }
  if (n === 0) return { nota: "sin_visibles" };
  return { media: suma / n, menos_de_5: visibles.some((c) => c.menos_de_5) || undefined };
}

export function tablaProfesor(informe: InformeProfesor): TablaProfesor {
  const etapas = etapasDelInforme(informe);
  const porPares = etapas.length >= 2;
  const colegio = !!informe.comparacion.colegio;
  const columnas: ColumnaTabla[] = [
    { tipo: "docente" },
    ...etapas.flatMap((etapa): ColumnaTabla[] => porPares ? [{ tipo: "docente_etapa", etapa }, { tipo: "etapa", etapa }] : [{ tipo: "etapa", etapa }]),
    ...(colegio ? [{ tipo: "colegio" } as const] : []),
  ];
  const usadas = new Set<NotaTabla>();

  const filas = informe.preguntas.map(({ codigo, texto, resultado: r }) => {
    const valores = columnas.map((col): ValorTabla => {
      switch (col.tipo) {
        case "docente":
          return r.global.suprimido ? mediaDocente(r.celdas) : { media: r.global.media!, menos_de_5: !!r.global.menos_de_5 || undefined };
        case "docente_etapa":
          return mediaDocente(r.celdas.filter((c) => c.etapa === col.etapa));
        case "etapa": {
          const ref = r.comparacion[col.etapa];
          if (ref) return deFila(ref);
          return { nota: r.celdas.some((c) => c.etapa === col.etapa) ? "sin_datos" : "no_se_pregunta" };
        }
        case "colegio": {
          const ref = r.comparacion.colegio;
          if (ref) return deFila(ref);
          return { nota: informe.version === "docente" ? "no_se_muestra" : "sin_datos" };
        }
      }
    });
    for (const v of valores) if ("nota" in v) usadas.add(v.nota);
    return { codigo, texto, valores };
  });

  return { etapas, porPares, columnas, filas, notas: ORDEN_NOTAS.filter((x) => usadas.has(x)) };
}

/** Notas de los resultados ocultos de un conjunto de celdas (detalle por clase). */
export function notasDeCeldas(celdas: Pick<Fila, "suprimido" | "motivo">[]): NotaTabla[] {
  const usadas = new Set(celdas.filter((c) => c.suprimido).map(notaDeFila));
  return ORDEN_NOTAS.filter((x) => usadas.has(x));
}

const mismaClase = (a: CeldaProfesor, b: CeldaProfesor) =>
  a.clave.cuestionario === b.clave.cuestionario && a.clave.grupo === b.clave.grupo && a.clave.asignatura === b.clave.asignatura;

/** Preguntas que se hacen en una clase, con su celda (solo esas: en el detalle por clase no hay huecos). */
export function deLaClase(preguntas: InformeProfesor["preguntas"], c: CeldaProfesor) {
  return preguntas.flatMap(({ codigo, texto, resultado }) => {
    const x = resultado.celdas.find((y) => mismaClase(y, c));
    return x ? [{ codigo, texto, x }] : [];
  });
}
