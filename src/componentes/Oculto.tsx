// Cómo se presenta un resultado suprimido (§5.8): «menos de 5» si tiene menos de 5
// respuestas; «oculto» si es por supresión complementaria. Nunca se muestra el número.

import type { Fila } from "../data/resultados";
import { t } from "../i18n";

export function Oculto({ fila }: { fila: Fila }) {
  if (fila.motivo === "sin_datos") {
    return <span className="en-oculto" title={t.sin_datos}>{t.sin_datos}</span>;
  }
  const menos5 = fila.motivo === "menos_de_5";
  return (
    <span className="en-oculto" title={menos5 ? t.oculto_tip_menos5 : t.oculto_tip}>
      {menos5 ? t.oculto_menos5 : t.oculto_compl}
    </span>
  );
}
