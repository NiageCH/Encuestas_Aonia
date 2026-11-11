// Tablas de los informes de tutoría y de servicios (§7.12 y §7.13): las mismas en pantalla, en el PDF (las dos
// versiones) y en el enlace personal. No calcula nada: junta las celdas que manda el servidor, ya con el criterio de la
// versión, y pone una nota en lugar de un hueco cuando una celda no lleva cifra (como el informe del profesor/a).

import type { Fila } from "./resultados";
import type { NotaTabla } from "./tablaProfesor";
import type { InformeServicio, InformeTutoria } from "./tutoriaServicios";
import { t } from "../i18n";

export type NotaResumen = Extract<NotaTabla, "menos_de_5" | "complementaria" | "sin_datos" | "no_se_pregunta">;
export type ValorResumen = { media: number; n: number; menos_de_5?: boolean } | { nota: NotaResumen };

export interface FilaResumen { codigo: string; texto: string; /** Preguntas propias del servicio, debajo de la principal. */ secundaria?: boolean; valores: ValorResumen[] }

export interface TablaResumen {
  clave: string;
  titulo: string;
  lead: string;
  columnas: string[];
  filas: FilaResumen[];
  /** Media de todos los servicios del colectivo, como referencia (informe de servicio). */
  referencia?: { texto: string; valor: ValorResumen };
  notas: NotaResumen[];
}

const ORDEN_NOTAS: NotaResumen[] = ["menos_de_5", "complementaria", "sin_datos", "no_se_pregunta"];
const ORDEN_ETAPAS = ["infantil", "primaria", "pai", "bachillerato"];
const etapa = (e: string) => t.etapas[e as keyof typeof t.etapas] ?? e;

/** Lo que va en una celda: la media y su número de valoraciones, o por qué no hay cifra. */
export function valorResumen(f: Fila | undefined): ValorResumen {
  if (!f) return { nota: "no_se_pregunta" };
  if (f.suprimido) return { nota: f.motivo === "menos_de_5" ? "menos_de_5" : f.motivo === "sin_datos" ? "sin_datos" : "complementaria" };
  if (f.media == null) return { nota: "sin_datos" };
  return { media: f.media, n: f.n_valoraciones ?? f.n ?? 0, ...(f.menos_de_5 ? { menos_de_5: true } : {}) };
}

function notasDe(filas: FilaResumen[], referencia?: TablaResumen["referencia"]): NotaResumen[] {
  const vistas = new Set<NotaResumen>();
  for (const v of [...filas.flatMap((x) => x.valores), ...(referencia ? [referencia.valor] : [])]) if ("nota" in v) vistas.add(v.nota);
  return ORDEN_NOTAS.filter((n) => vistas.has(n));
}

/** Informe de tutoría: lo que dice el alumnado del grupo de su tutor/a, con la etapa como referencia, y la labor
 *  tutorial según las familias y el personal, solo como referencia del Colegio. */
export function tablasTutoria(inf: InformeTutoria): TablaResumen[] {
  const tablas: TablaResumen[] = [];
  const g = inf.grupo;
  if (inf.preguntas.length > 0) {
    const filas = inf.preguntas.map((p) => ({ codigo: p.codigo, texto: p.texto, valores: [valorResumen(p.grupo), valorResumen(p.etapa)] }));
    tablas.push({
      clave: "grupo", titulo: t.tut_tabla_grupo(g.nombre), lead: t.tut_tabla_grupo_lead(etapa(g.etapa)),
      columnas: [t.tut_col_grupo(g.nombre), t.tut_col_etapa(etapa(g.etapa))], filas, notas: notasDe(filas),
    });
  }
  if (inf.colegio.length > 0) {
    const filas = inf.colegio.map((p) => ({ codigo: p.codigo, texto: `${t.tut_colectivo[p.colectivo]}: ${p.texto}`, valores: [valorResumen(p.total)] }));
    tablas.push({ clave: "colegio", titulo: t.tut_tabla_colegio, lead: t.tut_tabla_colegio_lead, columnas: [t.tut_col_colegio], filas, notas: notasDe(filas) });
  }
  return tablas;
}

/** Informe de servicio: una tabla por colectivo, con el total y cada etapa en la que se pregunta. */
export function tablasServicio(inf: InformeServicio): TablaResumen[] {
  return inf.colectivos.map((c) => {
    const presentes = new Set(c.preguntas.flatMap((p) => p.etapas.map((e) => e.clave.etapa)));
    const etapas = ORDEN_ETAPAS.filter((e) => presentes.has(e));
    const filas: FilaResumen[] = c.preguntas.map((p) => ({
      codigo: p.codigo,
      texto: p.principal ? t.srv_principal(p.texto) : p.texto,
      ...(p.principal ? {} : { secundaria: true }),
      valores: [valorResumen(p.total), ...etapas.map((e) => valorResumen(p.etapas.find((x) => x.clave.etapa === e)))],
    }));
    const referencia = c.servicios ? { texto: t.srv_referencia[c.colectivo], valor: valorResumen(c.servicios) } : undefined;
    return {
      clave: c.colectivo, titulo: t.srv_tabla[c.colectivo],
      lead: c.colectivo === "familias" ? `${t.srv_tabla_lead[c.colectivo]} ${t.fam_aviso_etapas}` : t.srv_tabla_lead[c.colectivo],
      columnas: [t.srv_col_total[c.colectivo], ...etapas.map(etapa)], filas, referencia, notas: notasDe(filas, referencia),
    };
  });
}
