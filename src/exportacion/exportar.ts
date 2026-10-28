// Descarga de una exportación (CSV o PDF de una vista, o el registro de descargas). Antes de crear el archivo, el servidor
// la anota en el registro de descargas (y la rechaza si quien la pide no puede ver esa vista) y devuelve el código, el
// nombre y la hora que van en el archivo. El PDF se carga bajo demanda y sale protegido (src/pdf/proteger.ts).

import { AVISO_VALIDACION } from "../ajustes";
import { registrarDescarga } from "../data/descargas";
import { aCsv, nombreArchivo } from "./csv";
import { hayMenos5, type Exportacion } from "./modelo";
import { t } from "../i18n";

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

export async function exportar(exp: Exportacion, formato: "csv" | "pdf"): Promise<void> {
  // Con cifras de menos de 5 (Dirección y administración), la nota que explica la marca.
  const e = hayMenos5(exp)
    ? { ...exp, notas: [...exp.notas.map((n) => (n === t.aviso_cierre ? t.aviso_cierre_direccion : n)), t.leyenda_menos5] }
    : exp;
  const archivo = e.sinCurso ? `${e.archivo.join("_")}.${formato}` : nombreArchivo(e.archivo, formato);
  const sello = await registrarDescarga(formato === "csv" ? "csv" : "vista_pdf", {
    objeto: e.titulo, vista: e.vista, filtros: Object.fromEntries(e.filtros), archivo,
  });
  if (formato === "csv") {
    descargar(new Blob([aCsv(e, sello, AVISO_VALIDACION)], { type: "text/csv;charset=utf-8" }), archivo);
    return;
  }
  const [{ pdf }, { createElement }, { ExportacionPdf }, { protegerPdf }] = await Promise.all([
    import("@react-pdf/renderer"), import("react"), import("./ExportacionPdf"), import("../pdf/proteger"),
  ]);
  const doc = createElement(ExportacionPdf, { exportacion: e, sello, aviso: AVISO_VALIDACION });
  const blob = await pdf(doc as Parameters<typeof pdf>[0]).toBlob();
  descargar(new Blob([await protegerPdf(blob, { titulo: e.titulo })], { type: "application/pdf" }), archivo);
}
