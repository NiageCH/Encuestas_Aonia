// Cuándo puede la web pedir resultados y cómo interpretar la respuesta (26/10/2026). Módulo puro, con tests.
//
// Un administrador cuya sesión no ha pasado el doble factor no ve ninguna pantalla de resultados ni pide ningún dato:
// primero, el código. Y la pregunta «¿hay resultados cargados?» distingue tres casos: no hay datos, no tienes acceso
// (el servidor lo deniega) o no se ha podido cargar (cualquier otro fallo). Solo el primero es el estado vacío.

import type { Colectivo } from "./data/resultados";

/** Nivel de autenticación del token (aal1 o aal2). El payload va en base64url. */
export function nivelAcceso(token: string | undefined | null): string | null {
  try {
    const b64 = (token ?? "").split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(b64.padEnd(Math.ceil(b64.length / 4) * 4, "="))).aal ?? null;
  } catch {
    return null;
  }
}

/** ¿Puede esta sesión ver resultados? Un administrador, solo con el doble factor pasado (salvo en local, si está desactivado). */
export function puedeVerResultados(rol: string | undefined, activo: boolean | undefined, mfaObligatorio: boolean | undefined, aal: string | null): boolean {
  if (!activo || mfaObligatorio === undefined) return false;
  return rol !== "administrador" || mfaObligatorio === false || aal === "aal2";
}

export type EstadoCarga =
  | { estado: "cargando" }
  | { estado: "listo"; colectivos: Colectivo[] }
  | { estado: "sin_acceso" }
  | { estado: "error" };

/** Un fallo al preguntar qué hay cargado: si el servidor lo deniega (42501), «sin acceso»; si no, «error». */
export function estadoDeError(e: unknown): EstadoCarga {
  const codigo = (e as { code?: string } | null)?.code;
  return codigo === "42501" ? { estado: "sin_acceso" } : { estado: "error" };
}

/** ¿Hay resultados de alguno de estos colectivos? Mientras se carga, sí (para no enseñar el estado vacío antes de tiempo). */
export function hayResultados(e: EstadoCarga, colectivos: Colectivo[]): boolean {
  if (e.estado === "cargando") return true;
  if (e.estado === "listo") return colectivos.some((c) => e.colectivos.includes(c));
  return false;
}
