// Navegación (§7.0): rutas, direcciones antiguas y permisos por rol. Módulo puro (sin React)
// para poder probarlo. Los permisos de verdad los aplica el servidor; esto evita ofrecer en
// pantalla lo que un rol no puede ver.
//
//   #/                                  Inicio (panel general)
//   #/alumnos · #/familias
//   #/personal                          Encuesta de personal (no para la coordinación)
//   #/informes/<nivel>                  Informes por persona: direccion · equipos · departamentos · profesores · envio
//                                       (envío al profesorado, solo administración)
//   #/abiertas                          Respuestas abiertas: solo Dirección y administración
//   #/usuarios[/descargas]              Solo administradores: personas y actividad, o el registro de descargas
//
// Filtros en la dirección (navegar al detalle, 30/10/2026): «?clave=valor&…», solo las claves de PARAMETROS de cada
// pantalla. «volver» guarda la dirección de la que se llegó al pulsar un elemento (banda «Detalle», con «Volver»).

export type Rol = "administrador" | "direccion" | "coordinacion";
export type Seccion = "/" | "/alumnos" | "/familias" | "/personal" | "/abiertas" | "/informes" | "/usuarios";
export type Nivel = "direccion" | "equipos" | "departamentos" | "profesores" | "envio";

/** De arriba abajo en la jerarquía del colegio y, al final, el envío de los informes al profesorado. */
export const NIVELES: Nivel[] = ["direccion", "equipos", "departamentos", "profesores", "envio"];

export interface Ruta {
  seccion: Seccion;
  nivel?: Nivel;
  /** En Accesos: la pestaña del registro de descargas. */
  descargas?: boolean;
  /** Filtros y detalle en la dirección («?clave=valor»), en el orden de PARAMETROS. */
  filtro?: Record<string, string>;
}

/** Claves que acepta cada pantalla en la dirección. «ver»: apartado al que bajar; «volver»: de dónde se llegó. */
const COMUNES = ["ver", "volver"];
export const PARAMETROS: Record<string, string[]> = {
  "/alumnos": ["etapa", "cuestionario", "grupo", "bloque", "pregunta", ...COMUNES],
  "/familias": ["etapa", "bloque", "pregunta", ...COMUNES],
  "/personal": ["segmento", "bloque", "pregunta", ...COMUNES],
  "/informes/equipos": COMUNES,
  "/informes/departamentos": ["jefe", "departamento", ...COMUNES],
  "/informes/profesores": ["cuestionario", "grupo", "asignatura", "departamento", "profesor", "clase", ...COMUNES],
};

const clavePantalla = (r: Ruta) => (r.seccion === "/informes" ? `/informes/${r.nivel}` : r.seccion);

export function aHash(r: Ruta): string {
  const base = r.seccion === "/usuarios" && r.descargas ? "#/usuarios/descargas"
    : r.seccion === "/informes" ? `#/informes/${r.nivel}` : `#${r.seccion}`;
  const claves = PARAMETROS[clavePantalla(r)] ?? [];
  const pares = claves.filter((k) => r.filtro?.[k]).map((k) => `${k}=${encodeURIComponent(r.filtro![k])}`);
  return pares.length ? `${base}?${pares.join("&")}` : base;
}

/** Filtros de la dirección que acepta la pantalla de la ruta (las demás claves se descartan). */
function leerFiltro(r: Ruta, consulta: string): Ruta {
  const claves = PARAMETROS[clavePantalla(r)];
  if (!claves || !consulta) return r;
  const filtro: Record<string, string> = {};
  for (const par of consulta.split("&")) {
    const i = par.indexOf("=");
    if (i < 1) continue;
    const k = par.slice(0, i);
    let v: string;
    try { v = decodeURIComponent(par.slice(i + 1)); } catch { continue; }
    if (claves.includes(k) && v) filtro[k] = v;
  }
  return Object.keys(filtro).length ? { ...r, filtro } : r;
}

/** Niveles de «Informes por persona» que ve cada rol. */
export function nivelesPermitidos(rol: Rol): Nivel[] {
  if (rol === "coordinacion") return ["profesores"];
  return rol === "administrador" ? NIVELES : NIVELES.filter((n) => n !== "envio");
}

export function permitida(r: Ruta, rol: Rol): boolean {
  if (r.seccion === "/usuarios") return rol === "administrador";
  if (r.seccion === "/personal" || r.seccion === "/abiertas") return rol !== "coordinacion";
  if (r.seccion === "/informes") return !!r.nivel && nivelesPermitidos(rol).includes(r.nivel);
  return true;
}

/** Secciones del menú de arriba que ve cada rol, en orden. */
export function menu(rol: Rol): Seccion[] {
  const todas: Seccion[] = ["/", "/alumnos", "/familias", "/personal", "/abiertas", "/informes", "/usuarios"];
  return todas.filter((s) => s === "/informes" || permitida({ seccion: s }, rol));
}

const informes = (nivel: Nivel | undefined, rol: Rol): Ruta => {
  const permitidos = nivelesPermitidos(rol);
  return { seccion: "/informes", nivel: nivel && permitidos.includes(nivel) ? nivel : permitidos[0] };
};

/** Lee la dirección, aplica las antiguas y lleva a cada rol a la ruta permitida más cercana. */
export function leerRuta(hash: string, rol: Rol): Ruta {
  const [camino, ...resto] = hash.replace(/^#/, "").split("?");
  const r = rutaSinFiltro(camino.split("/").filter(Boolean), rol);
  // Una dirección antigua o no permitida lleva a otra pantalla: sus filtros no valen allí.
  const pedida = "#" + camino.replace(/\/$/, "");
  return pedida === aHash(r) ? leerFiltro(r, resto.join("?")) : r;
}

function rutaSinFiltro(partes: string[], rol: Rol): Ruta {
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
  const r: Ruta = partes[0] === "usuarios" && partes[1] === "descargas" ? { seccion: "/usuarios", descargas: true }
    : ["alumnos", "familias", "abiertas", "usuarios"].includes(partes[0]) ? { seccion: `/${partes[0]}` as Seccion } : { seccion: "/" };
  return permitida(r, rol) ? r : { seccion: "/" };
}
