// Navegación (§7.0): rutas, direcciones antiguas y permisos por rol. Módulo puro (sin React)
// para poder probarlo. Los permisos de verdad los aplica el servidor; esto evita ofrecer en
// pantalla lo que un rol no puede ver.
//
//   #/                                  Inicio (panel general)
//   #/alumnos · #/familias
//   #/personal/encuesta                 Encuesta de personal
//   #/personal/informes/<nivel>         Informes por persona: direccion · equipos · departamentos · profesores
//   #/usuarios                          Solo administradores

export type Rol = "administrador" | "direccion" | "coordinacion";
export type Seccion = "/" | "/alumnos" | "/familias" | "/personal" | "/usuarios";
export type Nivel = "direccion" | "equipos" | "departamentos" | "profesores";

/** De arriba abajo en la jerarquía del colegio. */
export const NIVELES: Nivel[] = ["direccion", "equipos", "departamentos", "profesores"];

export interface Ruta {
  seccion: Seccion;
  apartado?: "encuesta" | "informes";
  nivel?: Nivel;
}

export function aHash(r: Ruta): string {
  if (r.seccion !== "/personal") return `#${r.seccion}`;
  return r.apartado === "informes" ? `#/personal/informes/${r.nivel}` : "#/personal/encuesta";
}

/** Niveles de «Informes por persona» que ve cada rol. */
export function nivelesPermitidos(rol: Rol): Nivel[] {
  return rol === "coordinacion" ? ["profesores"] : NIVELES;
}

export function permitida(r: Ruta, rol: Rol): boolean {
  if (r.seccion === "/usuarios") return rol === "administrador";
  if (r.seccion !== "/personal") return true;
  if (rol === "coordinacion") return r.apartado === "informes" && r.nivel === "profesores";
  return true;
}

/** Lee la dirección, aplica las antiguas y lleva a cada rol a la ruta permitida más cercana. */
export function leerRuta(hash: string, rol: Rol): Ruta {
  const partes = hash.replace(/^#/, "").split("?")[0].split("/").filter(Boolean);
  let r: Ruta;
  if (partes[0] === "profesorado") r = { seccion: "/personal", apartado: "informes", nivel: "profesores" };
  else if (partes[0] === "responsables") r = { seccion: "/personal", apartado: "informes", nivel: "direccion" };
  else if (partes[0] === "personal") {
    if (partes[1] === "informes") {
      const nivel = NIVELES.includes(partes[2] as Nivel) ? (partes[2] as Nivel) : nivelesPermitidos(rol)[0];
      r = { seccion: "/personal", apartado: "informes", nivel };
    } else {
      r = { seccion: "/personal", apartado: "encuesta" };
    }
  } else if (["alumnos", "familias", "usuarios"].includes(partes[0])) {
    r = { seccion: `/${partes[0]}` as Seccion };
  } else {
    r = { seccion: "/" };
  }

  if (permitida(r, rol)) return r;
  // La coordinación que pide cualquier parte de Personal llega a su único apartado.
  if (r.seccion === "/personal") return { seccion: "/personal", apartado: "informes", nivel: "profesores" };
  return { seccion: "/" };
}
