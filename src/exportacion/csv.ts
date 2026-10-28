// CSV pensado para Excel en español: UTF-8 con BOM (para que Excel lea bien los acentos), separador
// punto y coma y decimales con coma. Primero la cabecera (colegio, curso, vista, filtros, fecha y,
// si está activa, la franja de validación) y después cada tabla con su título y sus notas.

import { CURSO } from "../data/cliente";
import { redondear } from "../formato";
import { t } from "../i18n";
import type { Exportacion, SelloDescarga, Valor } from "./modelo";

const SEP = ";";
const FIN = "\r\n";

/** Número para Excel en español: coma decimal, signo menos ASCII y sin separador de miles. */
export function numeroCsv(x: number, dec: number): string {
  const r = redondear(x, dec);
  return (Object.is(r, -0) ? 0 : r).toFixed(dec).replace(".", ",");
}

/** Comillas si hace falta (separador, comillas o salto de línea). Excel no necesita más. */
const comillas = (s: string) => (/[";\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s);

/** Campo de texto de la plataforma: los espacios que no se parten (rangos, src/rangos.ts) vuelven a ser normales. */
export function campoCsv(s: string): string {
  return comillas(s.replace(/\u00a0/g, " "));
}

function valor(v: Valor): string {
  if ("num" in v) return v.marca ? campoCsv(`${numeroCsv(v.num, v.dec)} (${v.marca})`) : numeroCsv(v.num, v.dec);
  if ("oculto" in v) return campoCsv(v.oculto);
  if ("enunciado" in v) return comillas(v.enunciado);   // exactamente como está guardado
  return campoCsv(v.texto);
}

const linea = (xs: string[]) => xs.join(SEP);

/** Fecha y hora de la exportación: 22/10/2026 16:05. */
export function fechaExportacion(d: Date): string {
  const dos = (n: number) => String(n).padStart(2, "0");
  return `${dos(d.getDate())}/${dos(d.getMonth() + 1)}/${d.getFullYear()} ${dos(d.getHours())}:${dos(d.getMinutes())}`;
}

/** Texto de los filtros activos para la cabecera. */
export function textoFiltros(e: Pick<Exportacion, "filtros">): string {
  return e.filtros.length ? e.filtros.map(([k, v]) => `${k}: ${v}`).join(" · ") : t.exp_sin_filtros;
}

/** Cabecera de la exportación: quién la descargó, cuándo y con qué código, y de qué es. */
export function cabecera(e: Exportacion, sello: SelloDescarga, aviso: boolean): [string, string][] {
  return [
    [t.desc_por, sello.nombre],
    [t.desc_fecha, fechaExportacion(sello.fecha)],
    [t.desc_codigo, sello.codigo],
    [t.exp_colegio, t.colegio],
    ...(e.sinCurso ? [] : [[t.exp_curso, t.exp_curso_valor(CURSO)] as [string, string]]),
    [t.exp_vista, e.titulo],
    [t.exp_filtros, textoFiltros(e)],
    ...(aviso ? [[t.exp_aviso, t.aviso_validacion] as [string, string]] : []),
  ];
}

/** El CSV empieza por el aviso de confidencialidad y la cabecera (src/exportacion/csv.ts, cabecera). */
export function aCsv(e: Exportacion, sello: SelloDescarga, aviso: boolean): string {
  const lineas: string[] = [campoCsv(t.desc_confidencial_csv),
    ...cabecera(e, sello, aviso).map(([k, v]) => linea([campoCsv(k), campoCsv(v)]))];
  for (const tabla of e.tablas) {
    lineas.push("", campoCsv(tabla.titulo));
    if (tabla.filas.length) lineas.push(linea(tabla.columnas.map(campoCsv)));
    for (const fila of tabla.filas) lineas.push(linea(fila.map(valor)));
    for (const nota of tabla.notas ?? []) lineas.push(linea([t.exp_nota, campoCsv(nota)]));
  }
  if (e.notas.length) {
    lineas.push("");
    for (const nota of e.notas) lineas.push(linea([t.exp_nota, campoCsv(nota)]));
  }
  return "\uFEFF" + lineas.join(FIN) + FIN;
}

/** Encuestas_2526_Familias_Etapa-PAI.csv: sin acentos ni espacios. */
export function nombreArchivo(partes: string[], extension: "csv" | "pdf"): string {
  const limpio = (x: string) => x.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/[^A-Za-z0-9-]+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "");
  const curso = CURSO.replace(/\D/g, "").slice(2);   // 2025/26 -> 2526
  return ["Encuestas", curso, ...partes.map(limpio).filter(Boolean)].join("_") + "." + extension;
}
