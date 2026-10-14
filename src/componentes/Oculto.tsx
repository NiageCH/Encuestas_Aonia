// Cómo se presenta un resultado suprimido (§5.8): «menos de 5» si tiene menos de 5
// respuestas; «oculto» si es por supresión complementaria. Nunca se muestra el número.
// La explicación del motivo la da la información emergente del elemento que lo contiene.

import type { Fila } from "../data/resultados";
import { t } from "../i18n";

export function Oculto({ fila }: { fila: Fila }) {
  if (fila.motivo === "sin_datos") {
    return <span className="en-oculto">{t.sin_datos}</span>;
  }
  const menos5 = fila.motivo === "menos_de_5";
  return (
    <span className="en-oculto">
      {menos5 ? t.oculto_menos5 : t.oculto_compl}
    </span>
  );
}
