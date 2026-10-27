// Términos descartados en los textos de la interfaz (revisión de lenguaje de Aonia, docs/GLOSARIO.md), con el término
// aprobado. Lo usa glosario.test.ts sobre todo I18N.es. No se aplica a los enunciados de las preguntas, que vienen de la
// base de datos y no se tocan.

export const DESCARTADOS: { patron: RegExp; usar: string }[] = [
  { patron: /\balumnos\b/i, usar: "alumnado (alumno/a solo en singular inevitable)" },
  { patron: /\bprofesores\b/i, usar: "profesorado o docentes" },
  { patron: /\bprofesor\b(?!\/a)/i, usar: "profesor/a o docente" },
  { patron: /\btutores\b/i, usar: "profesorado tutor" },
  { patron: /puntos fuertes|puntos de mejora/i, usar: "Aspectos con mayor y menor valoración (Mayor valoración, Menor valoración)" },
  { patron: /lo más valorado/i, usar: "Aspectos más destacados" },
  { patron: /lo menos elegido/i, usar: "Aspectos menos destacados" },
  { patron: /con entusiasmo/i, usar: "Respuestas favorables (9 y 10)" },
  { patron: /\bneutral\b/i, usar: "Respuestas neutras (7 y 8)" },
  { patron: /detractor|promotor|defensores|críticos/i, usar: "Respuestas desfavorables o favorables" },
  { patron: /entra en cada una/i, usar: "Selecciona un colectivo para consultar sus resultados detallados" },
  { patron: /lo que tienen en común/i, usar: "Comparación de indicadores comunes entre colectivos" },
  { patron: /quienes no (lo )?recomendar[íi]an/i, usar: "Diferencias entre respuestas favorables y desfavorables a la recomendación" },
  { patron: /\bjefes?\b/i, usar: "jefatura (de departamento, de equipo)" },
  { patron: /superior(es)? directos?/i, usar: "persona responsable directa" },
  { patron: /\badministrador(es)?\b/i, usar: "administración (rol y cuentas de administración)" },
  { patron: /\busuarios?\b/i, usar: "acceso (menú «Accesos») o cuenta" },
  { patron: /^bienvenid[oa]|bienvenid[oa] o bienvenid/i, usar: "Te damos la bienvenida" },
  { patron: /\bcolegio\b/, usar: "Colegio, con mayúscula" },
  { patron: /muy distint|lo que opina/i, usar: "un texto descriptivo, sin interpretaciones" },
];

/** Todos los textos de un diccionario, con su clave: cadenas, listas, objetos y el código de las funciones (sus plantillas). */
export function textosDe(x: unknown, clave = ""): [string, string][] {
  if (typeof x === "string") return [[clave, x]];
  if (typeof x === "function") return [[clave, x.toString()]];
  if (Array.isArray(x)) return x.flatMap((v, i) => textosDe(v, `${clave}[${i}]`));
  if (x && typeof x === "object") return Object.entries(x).flatMap(([k, v]) => textosDe(v, clave ? `${clave}.${k}` : k));
  return [];
}
