// Generación de los PDF en el navegador: individual y en lote (ZIP). Se carga bajo demanda
// (import dinámico) para no pesar en la carga inicial de la aplicación.
//
// Cada descarga: primero los datos (de las RPC de siempre, con sus permisos), después el registro en el servidor, que da
// el código, el nombre y la hora del pie, y por último el PDF con marca de agua, propiedades y restricciones. En un ZIP,
// cada PDF lleva su propio código y el ZIP el suyo, con la lista de informes.

import { pdf } from "@react-pdf/renderer";
import JSZip from "jszip";
import { createElement, type ReactElement } from "react";
import { registrarDescarga, type TipoDescarga } from "../data/descargas";
import {
  informeEquipo, informeJefe, informeProfesor, informeResponsable,
  type GrupoEquipo, type InformeProfesor, type Jefe, type Profesor, type TipoResponsable,
} from "../data/resultados";
import { notaReuniones, responsablesEquipo, textoAlumnos, tituloAlumnosJefe, tituloEquipo, tituloReuniones } from "../etiquetas";
import type { SelloDescarga } from "../exportacion/modelo";
import { t } from "../i18n";
import { InformeProfesorPdf } from "./InformeProfesorPdf";
import { InformeNivelPdf, type AlumnosDepartamentoPdf, type DatosNivelPdf, type SeccionPdf } from "./InformeNivelPdf";
import { protegerPdf } from "./proteger";

/** Informe_2526_Apellidos_Nombre.pdf, sin acentos ni caracteres raros. */
export function nombreFichero(p: Profesor): string {
  const limpio = (x: string) => x.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^A-Za-z0-9]+/g, "_").replace(/^_|_$/g, "");
  return `Informe_2526_${limpio(p.apellidos)}_${limpio(p.nombre)}.pdf`;
}

/** El PDF ya protegido (src/pdf/proteger.ts). */
async function pdfProtegido(doc: ReactElement, titulo: string): Promise<Blob> {
  const blob = await pdf(doc as Parameters<typeof pdf>[0]).toBlob();
  return new Blob([await protegerPdf(blob, { titulo })], { type: "application/pdf" });
}

const nombreDe = (p: Profesor) => `${p.nombre} ${p.apellidos}`;

function pdfProfesor(p: Profesor, informe: InformeProfesor, sello: SelloDescarga): Promise<Blob> {
  const doc = createElement(InformeProfesorPdf, {
    profesor: { nombre: p.nombre, apellidos: p.apellidos, departamento: p.departamento }, informe, sello,
  });
  return pdfProtegido(doc, `${t.prof_informe} · ${nombreDe(p)}`);
}

function descargar(blob: Blob, nombre: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = nombre;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

export async function descargarInforme(p: Profesor): Promise<void> {
  const informe = await informeProfesor(p.id, false);
  const sello = await registrarDescarga("informe_profesor", { objeto: nombreDe(p), docente: p.id, archivo: nombreFichero(p) });
  descargar(await pdfProfesor(p, informe, sello), nombreFichero(p));
}

export type FaseLote = "datos" | "pdf";

/** Un PDF por profesor en un ZIP. Primero los datos de todos (se puede cancelar); después se anota el ZIP, con un código
 *  por informe, y se generan los PDF. Llama a alProgresar(hechos, total, fase) tras cada paso. */
export async function descargarLote(profesores: Profesor[], alProgresar: (hechos: number, total: number, fase: FaseLote) => void,
                                    cancelado: () => boolean = () => false): Promise<number> {
  const datos: [Profesor, InformeProfesor][] = [];
  for (const p of profesores) {
    if (cancelado()) return 0;
    datos.push([p, await informeProfesor(p.id, true)]);
    alProgresar(datos.length, profesores.length, "datos");
  }
  if (datos.length === 0) return 0;
  const archivo = "Informes_profesorado_2526.zip";
  const zipSello = await registrarDescarga("zip", {
    objeto: t.desc_zip_objeto(datos.length), archivo, informes: datos.map(([p]) => ({ objeto: nombreDe(p), docente: p.id })),
  });
  const zip = new JSZip();
  for (const [i, [p, informe]] of datos.entries()) {
    zip.file(nombreFichero(p), await pdfProfesor(p, informe, zipSello.informes[i]));
    alProgresar(i + 1, datos.length, "pdf");
  }
  descargar(await zip.generateAsync({ type: "blob" }), archivo);
  return datos.length;
}

/** Lo que se anota de un informe de responsables: tipo y de quién es. */
interface RegistroNivel { tipo: TipoDescarga; objeto: string; persona?: number; tramos?: string[] }

export interface SeccionPedida {
  tipo: TipoResponsable; ambito: string | null; titulo: string; subtitulo: string; nota?: string; etiquetas: string[];
}

const limpio = (x: string) => x.normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^A-Za-z0-9]+/g, "_").replace(/^_|_$/g, "");

async function descargarNivel(nombre: string, datos: Omit<DatosNivelPdf, "sello">, registro: RegistroNivel): Promise<void> {
  const archivo = `Informe_2526_${limpio(nombre)}.pdf`;
  const sello = await registrarDescarga(registro.tipo, { ...registro, archivo });
  const doc = createElement(InformeNivelPdf, { ...datos, sello });
  descargar(await pdfProtegido(doc, `${datos.eyebrow} · ${datos.titulo}`), archivo);
}

/** PDF de un nivel de «Informes por persona» (Dirección, todo el Equipo de Individuación):
 *  Informe_2526_<nombre>.pdf. Cada sección pedida queda en el registro de actividad. */
export async function descargarInformeNivel(opciones: {
  nombre: string; eyebrow: string; titulo: string; subtitulo: string; secciones: SeccionPedida[];
}): Promise<void> {
  const secciones = await Promise.all(opciones.secciones.map(async (x) => ({
    ...x, informe: await informeResponsable(x.tipo, x.ambito, true),
  })));
  await descargarNivel(opciones.nombre, { eyebrow: opciones.eyebrow, titulo: opciones.titulo, subtitulo: opciones.subtitulo, secciones },
    { tipo: opciones.nombre === "Direccion" ? "informe_direccion" : "informe_equipo", objeto: opciones.titulo });
}

/** PDF de un jefe de departamento con todos sus departamentos (queda en el registro). */
export async function descargarInformeJefe(jefe: Jefe): Promise<void> {
  const inf = await informeJefe(jefe.id, true);
  const secciones: SeccionPdf[] = inf.reuniones.map((r) => ({
    titulo: tituloReuniones(r), subtitulo: t.resp_departamento_sub,
    nota: notaReuniones(r, inf.departamentos, inf.reuniones.length), etiquetas: t.escala_acuerdo_dep, informe: r,
  }));
  const alumnos: AlumnosDepartamentoPdf[] = [{ titulo: tituloAlumnosJefe(inf.alumnos.departamentos), ...textoAlumnos(inf.alumnos.media) }];
  await descargarNivel(`Departamentos_${jefe.apellidos}_${jefe.nombre}`, {
    eyebrow: t.resp_informe, titulo: `${jefe.nombre} ${jefe.apellidos}`, subtitulo: t.jefe_departamentos(inf.departamentos),
    secciones, alumnos, sinSecciones: t.jefe_sin_reuniones,
  }, { tipo: "informe_jefatura", objeto: `${jefe.nombre} ${jefe.apellidos}`, persona: jefe.id });
}

/** PDF del Equipo de Individuación de un tramo o de varios juntos (queda en el registro). */
export async function descargarInformeEquipo(g: GrupoEquipo): Promise<void> {
  const inf = await informeEquipo(g.tramos, true);
  await descargarNivel(`Equipo_Individuacion_${g.tramos.join("_")}`, {
    eyebrow: t.resp_informe, titulo: tituloEquipo(g.tramos),
    subtitulo: g.responsables.length ? `${t.eq_responsables}: ${responsablesEquipo(g)}` : t.resp_equipo,
    secciones: [{
      titulo: t.resp_equipo, subtitulo: t.eq_sub_tramo, etiquetas: t.escala_acuerdo_per, informe: inf,
      nota: g.tramos.length > 1 ? t.eq_compartido_nota : undefined,
    }],
  }, { tipo: "informe_equipo", objeto: tituloEquipo(g.tramos), tramos: g.tramos });
}
