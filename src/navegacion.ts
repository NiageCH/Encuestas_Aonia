// Navegación (§7.0): rutas, direcciones antiguas y permisos por rol. Módulo puro (sin React)
// para poder probarlo. Los permisos de verdad los aplica el servidor; esto evita ofrecer en
// pantalla lo que un rol no puede ver.
//
//   #/                                  Inicio (panel general)
//   #/alumnos · #/familias
//   #/personal                          Encuesta de personal (no para la coordinación)
//   #/informes/<nivel>                  Informes por persona: direccion · equipos · departamentos · profesores
//   #/usuarios                          Solo administradores

export type Rol = "administrador" | "direccion" | "coordinacion";
export type Seccion = "/" | "/alumnos" | "/familias" | "/personal" | "/informes" | "/usuarios";
export type Nivel = "direccion" | "equipos" | "departamentos" | "profesores";

/** De arriba abajo en la jerarquía del colegio. */
export const NIVELES: Nivel[] = ["direccion", "equipos", "departamentos", "profesores"];

export interface Ruta {
  seccion: Seccion;
  nivel?: Nivel;
}

export function aHash(r: Ruta): string {
  return r.seccion === "/informes" ? `#/informes/${r.nivel}` : `#${r.seccion}`;
}

/** Niveles de «Informes por persona» que ve cada rol. */
export function nivelesPermitidos(rol: Rol): Nivel[] {
  return rol === "coordinacion" ? ["profesores"] : NIVELES;
}

export function permitida(r: Ruta, rol: Rol): boolean {
  if (r.seccion === "/usuarios") return rol === "administrador";
  if (r.seccion === "/personal") return rol !== "coordinacion";
  if (r.seccion === "/informes") return !!r.nivel && nivelesPermitidos(rol).includes(r.nivel);
  return true;
}

/** Secciones del menú de arriba que ve cada rol, en orden. */
export function menu(rol: Rol): Seccion[] {
  const todas: Seccion[] = ["/", "/alumnos", "/familias", "/personal", "/informes", "/usuarios"];
  return todas.filter((s) => s === "/informes" || permitida({ seccion: s }, rol));
}

const informes = (nivel: Nivel | undefined, rol: Rol): Ruta => {
  const permitidos = nivelesPermitidos(rol);
  return { seccion: "/informes", nivel: nivel && permitidos.includes(nivel) ? nivel : permitidos[0] };
};

/** Lee la dirección, aplica las antiguas y lleva a cada rol a la ruta permitida más cercana. */
export function leerRuta(hash: string, rol: Rol): Ruta {
  const partes = hash.replace(/^#/, "").split("?")[0].split("/").filter(Boolean);
  const nivel = (x: string | undefined) => (NIVELES.includes(x as Nivel) ? (x as Nivel) : undefined);
  // Direcciones antiguas
  if (partes[0] === "profesorado") return informes("profesores", rol);
  if (partes[0] === "responsables") return informes("direccion", rol);
  if (partes[0] === "personal" && partes[1] === "informes") return informes(nivel(partes[2]), rol);
  // Actuales
  if (partes[0] === "informes") return informes(nivel(partes[1]), rol);
  if (partes[0] === "personal") {
    // La coordinación solo tiene los informes de sus profesores.
    return rol === "coordinacion" ? informes("profesores", rol) : { seccion: "/personal" };
  }
  const r: Ruta = ["alumnos", "familias", "usuarios"].includes(partes[0]) ? { seccion: `/${partes[0]}` as Seccion } : { seccion: "/" };
  return permitida(r, rol) ? r : { seccion: "/" };
}
