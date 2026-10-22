// Etiquetas compartidas por la vista y los PDF.

import type { CeldaProfesor, GrupoEquipo, MediaDepartamentoAlumnos, SeccionReuniones } from "./data/resultados";
import * as f from "./formato";
import { t } from "./i18n";

/** «Asignatura · grupo», con la marca de atribución o el número de docentes de la clase. */
export function etiquetaClase(c: CeldaProfesor): string {
  const grupo = c.clave.grupo ?? t.prof_todos_grupos;
  if (c.tipo === "atribuida") return `${c.clave.asignatura} · ${grupo} (${t.prof_atribuida})`;
  if (c.tipo === "compartida") return `${c.clave.asignatura} · ${grupo} (${t.prof_docentes_clase(c.docentes_clase)})`;
  return `${c.clave.asignatura} · ${grupo}`;
}

/** Ordena por asignatura y grupo (las de todos los grupos, al final de su asignatura). */
export function ordenarClases<T extends CeldaProfesor>(celdas: T[]): T[] {
  return [...celdas].sort((a, b) =>
    a.clave.asignatura.localeCompare(b.clave.asignatura, "es")
    || (a.clave.grupo ?? "~").localeCompare(b.clave.grupo ?? "~", "es", { numeric: true }));
}

/** Lista en español: «A», «A y B», «A, B y C». */
export function enumerar(xs: string[]): string {
  return xs.length <= 1 ? (xs[0] ?? "") : `${xs.slice(0, -1).join(", ")} y ${xs[xs.length - 1]}`;
}

/** Título y nota de una sección de reuniones del informe de un jefe de departamento. */
export function tituloReuniones(sec: SeccionReuniones): string {
  return sec.conjunto ? t.jefe_reuniones_conjunto : t.jefe_reuniones_unidad(sec.unidades[0]);
}
export function notaReuniones(sec: SeccionReuniones, departamentos: string[], secciones: number): string | undefined {
  if (sec.conjunto) return t.jefe_conjunto_nota;
  if (secciones === 1 && departamentos.length > 1) return t.jefe_unidad_varios;
  return undefined;
}

/** «Tutores de Infantil y Y1 a Y5». */
export function tituloEquipo(tramos: string[]): string {
  return t.eq_titulo(enumerar(tramos.map((x) => t.eq_tramos[x] ?? x)));
}
export function responsablesEquipo(g: GrupoEquipo): string {
  return enumerar(g.responsables.map((r) => `${r.nombre} ${r.apellidos}`));
}

/** Título de la media de alumnos de un jefe: su departamento, o «sus departamentos» si tiene varios. */
export function tituloAlumnosJefe(departamentos: string[]): string {
  return departamentos.length === 1 ? t.jefe_alumnos(departamentos[0]) : t.jefe_alumnos_varios;
}

/** Media de los profesores de un departamento según los alumnos, en texto. */
export function textoAlumnos(m: MediaDepartamentoAlumnos): { texto: string; detalle?: string; nota?: string } {
  if (m.global.suprimido && m.global.motivo === "solo_compartidas") return { texto: t.dep_solo_compartidas_corto, nota: t.dep_solo_compartidas };
  if (m.global.suprimido) return { texto: m.global.motivo === "sin_asignacion" ? t.dep_alumnos_pendiente : t.prof_sin_visibles };
  return {
    texto: `${f.media(m.global.media!)} / 6`,
    detalle: t.dep_alumnos_detalle(m.profesores, m.global.combinaciones!, f.recuento(m.global.n_valoraciones!)),
    nota: m.combinaciones_excluidas > 0 ? t.prof_excluidas(m.combinaciones_excluidas) : undefined,
  };
}
