// Redondeo y formato de cifras (§3): se calcula con precisión completa y se redondea solo
// al mostrar, alejándose del cero en el medio punto. Coma decimal.

function redondear(x: number, decimales: number): number {
  const f = 10 ** decimales;
  // Corrige el error de coma flotante antes de redondear (4.675 -> 467.49999...).
  const v = Math.abs(x) * f;
  const r = Math.round(Number(v.toPrecision(12)));
  return (Math.sign(x) * r) / f;
}

function conComa(x: number, decimales: number): string {
  return redondear(x, decimales).toFixed(decimales).replace(".", ",").replace("-", "−");
}

/** Media de 1 a 6: dos decimales. */
export const media = (x: number) => conComa(x, 2);

/** Recomendación de 0 a 10: un decimal. */
export const recomendacion = (x: number) => conComa(x, 1);

/** Porcentaje entero. */
export const porcentaje = (x: number) => `${conComa(x, 0)} %`;

/** NPS entero con signo: +42, −65, 0. */
export function nps(x: number): string {
  const v = redondear(x, 0);
  return v > 0 ? `+${v}` : v < 0 ? `−${-v}` : "0";
}

/** Recuento con separador de miles. */
export const recuento = (n: number) => n.toLocaleString("es-ES");
