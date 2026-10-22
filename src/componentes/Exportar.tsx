// Botones «Exportar CSV» y «Exportar PDF» de cada vista (§7.6). preparar() reúne lo que se ve
// en pantalla con los filtros activos (y, si hace falta, el detalle de todos los bloques).

import { useState } from "react";
import type { Exportacion } from "../exportacion/modelo";
import { t } from "../i18n";

export function Exportar({ preparar, disabled }: { preparar: () => Promise<Exportacion>; disabled?: boolean }) {
  const [estado, setEstado] = useState<"" | "csv" | "pdf" | "error">("");
  async function pulsar(formato: "csv" | "pdf") {
    setEstado(formato);
    try {
      const [{ exportar }, e] = await Promise.all([import("../exportacion/exportar"), preparar()]);
      await exportar(e, formato);
      setEstado("");
    } catch {
      setEstado("error");
    }
  }
  const ocupado = estado === "csv" || estado === "pdf";
  return (
    <div className="en-exportar en-noprint">
      <span>{t.exp_titulo}</span>
      <button type="button" className="btn" onClick={() => pulsar("csv")} disabled={disabled || ocupado}>
        {estado === "csv" ? t.exp_generando : t.exp_csv}
      </button>
      <button type="button" className="btn" onClick={() => pulsar("pdf")} disabled={disabled || ocupado}>
        {estado === "pdf" ? t.exp_generando : t.exp_pdf}
      </button>
      {estado === "error" && <span className="en-error" role="alert">{t.exp_error}</span>}
    </div>
  );
}
