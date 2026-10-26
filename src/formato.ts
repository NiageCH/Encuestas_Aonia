// Redondeo y formato de cifras (§3): se calcula con precisión completa y se redondea solo
// al mostrar, alejándose del cero en el medio punto. Coma decimal.

export function redondear(x: number, decimales: number): number {
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

/** Primera letra en mayúscula (algunas preguntas de Encuesta Fácil empiezan en minúscula). No cambia el texto guardado. */
export function mayusculaInicial(texto: string): string {
  // La primera letra, aunque vaya detrás de «¿», «¡», comillas o espacios.
  return texto.replace(/^([\s¿¡«"“(]*)(\p{L})/u, (_, signos: string, letra: string) => signos + letra.toLocaleUpperCase("es"));
}

/** Aplica mayusculaInicial a todos los campos «texto» de una respuesta del servidor (preguntas de informes, detalle,
 *  puntos fuertes...). Así llega igual a la web, los PDF y los CSV, que salen de los mismos datos. */
export function textosConMayuscula<T>(x: T): T {
  if (Array.isArray(x)) return x.map(textosConMayuscula) as T;
  if (x && typeof x === "object") {
    return Object.fromEntries(Object.entries(x as Record<string, unknown>).map(([k, v]) =>
      [k, k === "texto" && typeof v === "string" ? mayusculaInicial(v) : textosConMayuscula(v)])) as T;
  }
  return x;
}
