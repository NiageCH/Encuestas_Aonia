// Generación de los PDF en el navegador: individual y en lote (ZIP). Se carga bajo demanda
// (import dinámico) para no pesar en la carga inicial de la aplicación.

import { pdf } from "@react-pdf/renderer";
import JSZip from "jszip";
import { createElement } from "react";
import { informeProfesor, informeResponsable, mediaDepartamentoAlumnos, type Profesor, type TipoResponsable } from "../data/resultados";
import * as f from "../formato";
import { t } from "../i18n";
import { InformeProfesorPdf } from "./InformeProfesorPdf";
import { InformeNivelPdf, type AlumnosDepartamentoPdf } from "./InformeNivelPdf";

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

/** PDF de un nivel de «Informes por persona»: Informe_2526_<nombre>.pdf. Cada sección pedida
 *  queda en el registro de actividad. */
export async function descargarInformeNivel(opciones: {
  nombre: string; eyebrow: string; titulo: string; subtitulo: string; secciones: SeccionPedida[]; departamento?: string;
}): Promise<void> {
  const secciones = await Promise.all(opciones.secciones.map(async (x) => ({
    ...x, informe: await informeResponsable(x.tipo, x.ambito, true),
  })));
  let alumnos: AlumnosDepartamentoPdf | undefined;
  if (opciones.departamento) {
    const m = await mediaDepartamentoAlumnos(opciones.departamento);
    alumnos = m.global.suprimido
      ? { texto: m.global.motivo === "sin_asignacion" ? t.dep_alumnos_pendiente : t.prof_sin_visibles }
      : { texto: `${f.media(m.global.media!)} / 6`, detalle: t.dep_alumnos_detalle(m.profesores, m.global.combinaciones!, f.recuento(m.global.n_valoraciones!)),
          nota: m.combinaciones_excluidas > 0 ? t.prof_excluidas(m.combinaciones_excluidas) : undefined };
  }
  const doc = createElement(InformeNivelPdf, {
    eyebrow: opciones.eyebrow, titulo: opciones.titulo, subtitulo: opciones.subtitulo, secciones, alumnos, generado: new Date(),
  });
  const blob = await pdf(doc as Parameters<typeof pdf>[0]).toBlob();
  const limpio = (x: string) => x.normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^A-Za-z0-9]+/g, "_").replace(/^_|_$/g, "");
  descargar(blob, `Informe_2526_${limpio(opciones.nombre)}.pdf`);
}
