// Descarga de una exportación. Antes de generar el archivo, el servidor la deja en el registro de
// actividad (y la rechaza si quien la pide no puede ver esa vista). El PDF se carga bajo demanda.

import { AVISO_VALIDACION } from "../ajustes";
import { supabase } from "../data/cliente";
import { aCsv, nombreArchivo } from "./csv";
import type { Exportacion } from "./modelo";

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

async function registrar(e: Exportacion, formato: "csv" | "pdf") {
  const { error } = await supabase.rpc("registrar_exportacion", {
    p_vista: e.vista, p_formato: formato, p_filtros: Object.fromEntries(e.filtros),
  });
  if (error) throw error;
}

export async function exportar(e: Exportacion, formato: "csv" | "pdf"): Promise<void> {
  await registrar(e, formato);
  const ahora = new Date();
  if (formato === "csv") {
    descargar(new Blob([aCsv(e, ahora, AVISO_VALIDACION)], { type: "text/csv;charset=utf-8" }), nombreArchivo(e.archivo, "csv"));
    return;
  }
  const [{ pdf }, { createElement }, { ExportacionPdf }] = await Promise.all([
    import("@react-pdf/renderer"), import("react"), import("./ExportacionPdf"),
  ]);
  const doc = createElement(ExportacionPdf, { exportacion: e, generado: ahora, aviso: AVISO_VALIDACION });
  descargar(await pdf(doc as Parameters<typeof pdf>[0]).toBlob(), nombreArchivo(e.archivo, "pdf"));
}
