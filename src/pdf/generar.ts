// Generación de los PDF en el navegador: individual y en lote (ZIP). Se carga bajo demanda
// (import dinámico) para no pesar en la carga inicial de la aplicación.

import { pdf } from "@react-pdf/renderer";
import JSZip from "jszip";
import { createElement } from "react";
import {
  informeEquipo, informeJefe, informeProfesor, informeResponsable,
  type GrupoEquipo, type Jefe, type Profesor, type TipoResponsable,
} from "../data/resultados";
import { notaReuniones, responsablesEquipo, textoAlumnos, tituloAlumnosJefe, tituloEquipo, tituloReuniones } from "../etiquetas";
import { t } from "../i18n";
import { InformeProfesorPdf } from "./InformeProfesorPdf";
import { InformeNivelPdf, type AlumnosDepartamentoPdf, type DatosNivelPdf, type SeccionPdf } from "./InformeNivelPdf";

/** Informe_2526_Apellidos_Nombre.pdf, sin acentos ni caracteres raros. */
export function nombreFichero(p: Profesor): string {
  const limpio = (x: string) => x.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^A-Za-z0-9]+/g, "_").replace(/^_|_$/g, "");
  return `Informe_2526_${limpio(p.apellidos)}_${limpio(p.nombre)}.pdf`;
}

async function blobInforme(p: Profesor, lote: boolean): Promise<Blob> {
  const informe = await informeProfesor(p.id, lote);
  const doc = createElement(InformeProfesorPdf, {
    profesor: { nombre: p.nombre, apellidos: p.apellidos, departamento: p.departamento },
    informe, generado: new Date(),
  });
  return pdf(doc as Parameters<typeof pdf>[0]).toBlob();
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
  descargar(await blobInforme(p, false), nombreFichero(p));
}

/** Un PDF por profesor en un ZIP. Llama a alProgresar(hechos, total) tras cada informe. */
export async function descargarLote(profesores: Profesor[], alProgresar: (hechos: number, total: number) => void,
                                    cancelado: () => boolean = () => false): Promise<number> {
  const zip = new JSZip();
  let hechos = 0;
  for (const p of profesores) {
    if (cancelado()) break;
    zip.file(nombreFichero(p), await blobInforme(p, true));
    hechos += 1;
    alProgresar(hechos, profesores.length);
  }
  if (hechos > 0) {
    descargar(await zip.generateAsync({ type: "blob" }), "Informes_profesorado_2526.zip");
  }
  return hechos;
}

export interface SeccionPedida {
  tipo: TipoResponsable; ambito: string | null; titulo: string; subtitulo: string; nota?: string; etiquetas: string[];
}

const limpio = (x: string) => x.normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^A-Za-z0-9]+/g, "_").replace(/^_|_$/g, "");

async function descargarNivel(nombre: string, datos: Omit<DatosNivelPdf, "generado">): Promise<void> {
  const doc = createElement(InformeNivelPdf, { ...datos, generado: new Date() });
  const blob = await pdf(doc as Parameters<typeof pdf>[0]).toBlob();
  descargar(blob, `Informe_2526_${limpio(nombre)}.pdf`);
}

/** PDF de un nivel de «Informes por persona» (Dirección, todo el Equipo de Individuación):
 *  Informe_2526_<nombre>.pdf. Cada sección pedida queda en el registro de actividad. */
export async function descargarInformeNivel(opciones: {
  nombre: string; eyebrow: string; titulo: string; subtitulo: string; secciones: SeccionPedida[];
}): Promise<void> {
  const secciones = await Promise.all(opciones.secciones.map(async (x) => ({
    ...x, informe: await informeResponsable(x.tipo, x.ambito, true),
  })));
  await descargarNivel(opciones.nombre, { eyebrow: opciones.eyebrow, titulo: opciones.titulo, subtitulo: opciones.subtitulo, secciones });
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
  });
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
  });
}
