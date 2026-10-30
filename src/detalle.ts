// Navegar al detalle al pulsar (30/10/2026): direcciones de destino con su filtro y la dirección de origen («volver»).
// Módulo puro (sin React) para poder probarlo. Un destino que el rol no puede ver no existe: el elemento no se puede
// pulsar. Los permisos de verdad los sigue aplicando el servidor, con el mismo criterio de cada rol.

import { aHash, leerRuta, permitida, type Rol, type Ruta } from "./navegacion";

/** Claves que no son filtro: a qué apartado bajar, qué resaltar y de dónde se llegó. */
export const CLAVES_DETALLE = ["ver", "volver", "pregunta", "clase"];

/** La dirección sin «volver»: lo que se guarda como origen (un solo paso atrás, sin cadenas). */
export function sinVolver(hash: string): string {
  const [camino, consulta] = hash.split("?");
  if (!consulta) return hash;
  const resto = consulta.split("&").filter((p) => !p.startsWith("volver="));
  return resto.length ? `${camino}?${resto.join("&")}` : camino;
}

/** Dirección del detalle, con la de origen para «Volver». Sin destino si el rol no puede ver esa pantalla. */
export function destino(r: Ruta, rol: Rol, desde: string): string | undefined {
  if (!permitida(r, rol)) return undefined;
  const hash = aHash({ ...r, filtro: { ...r.filtro, volver: sinVolver(desde) } });
  // Solo destinos que la propia navegación reconoce tal cual (pantalla y filtros permitidos para el rol).
  return aHash(leerRuta(hash, rol)) === hash ? hash : undefined;
}

/** Los filtros de la ruta sin las claves de detalle (lo que se queda al quitar el detalle o al volver a filtrar). */
export function soloFiltros(filtro: Record<string, string> | undefined): Record<string, string> {
  return Object.fromEntries(Object.entries(filtro ?? {}).filter(([k]) => !CLAVES_DETALLE.includes(k)));
}

/** Aplica cambios a los filtros: un valor nulo o vacío quita la clave. */
export function conCambios(filtro: Record<string, string> | undefined, cambios: Record<string, string | null | undefined>) {
  const r: Record<string, string> = { ...filtro };
  for (const [k, v] of Object.entries(cambios)) {
    if (v) r[k] = v; else delete r[k];
  }
  return r;
}
