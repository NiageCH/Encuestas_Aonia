// Etiquetas de la escala de 1 a 6 de cada bloque del alumnado, tal como vienen en sus encuestas de 2025/26 (detalle por
// pregunta de Alumnado). Primaria usa otras palabras; los programas de Y6 a Y10 dicen «De acuerdo» en el 4.

import { t } from "./i18n";

const PROGRAMAS = new Set(["mindfulness", "encuentros", "narracion", "pasiones", "ignite", "eureka"]);

export function escalaAlumnos(etapa: string | null | undefined, bloque: string): string[] {
  if (etapa === "primaria") return bloque === "servicios" ? t.escala_gusto_pri : t.escala_frecuencia_pri;
  if (bloque === "profesorado") return t.escala_frecuencia_alu;
  if (bloque === "servicios") return t.escala_satisfaccion_alu;
  if (PROGRAMAS.has(bloque)) return t.escala_acuerdo_alu_programas;
  return t.escala_acuerdo_alu;
}
