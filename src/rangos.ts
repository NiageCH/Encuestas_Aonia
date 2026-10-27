// Rangos y escalas sin partir al final de una línea (revisión de lenguaje): «de 1 a 6», «(9 y 10)», «6 o menos»,
// «escala de 0 a 10», «% favorables». Usa espacios que no se parten; el CSV los vuelve a convertir en espacios normales.

export const sinCortes = (x: string) => x
  .replace(/(\d+) (a|y|o) (\d+|menos)/g, "$1 $2 $3")
  .replace(/\b(de|del) (\d)/g, "$1 $2")
  .replace(/% (de|favorables|neutras|desfavorables)/g, "% $1");

/** Aplica sinCortes a todos los textos de un diccionario, también a lo que devuelven sus funciones. */
export function conRangos<T>(x: T): T {
  if (typeof x === "string") return sinCortes(x) as T;
  if (typeof x === "function") {
    return ((...a: unknown[]) => { const r = (x as (...a: unknown[]) => unknown)(...a); return typeof r === "string" ? sinCortes(r) : r; }) as T;
  }
  if (Array.isArray(x)) return x.map(conRangos) as T;
  if (x && typeof x === "object") return Object.fromEntries(Object.entries(x).map(([k, v]) => [k, conRangos(v)])) as T;
  return x;
}
