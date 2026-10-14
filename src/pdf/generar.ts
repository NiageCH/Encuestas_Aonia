// Generación de los PDF en el navegador: individual y en lote (ZIP). Se carga bajo demanda
// (import dinámico) para no pesar en la carga inicial de la aplicación.

import { pdf } from "@react-pdf/renderer";
import JSZip from "jszip";
import { createElement } from "react";
import { informeProfesor, type Profesor } from "../data/resultados";
import { InformeProfesorPdf } from "./InformeProfesorPdf";

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
