import { useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { ProveedorAyuda } from "./componentes/Ayuda";
import { Marco, type Enlace } from "./componentes/Marco";
import { tipoEnlace } from "./data/cliente";
import { alCambiarSesion, miPerfil, salir, sesionActual, type Perfil } from "./data/sesion";
import { t } from "./i18n";
import { aHash, leerRuta } from "./navegacion";
import { Acceso } from "./vistas/Acceso";
import { Alumnos } from "./vistas/Alumnos";
import { DobleFactor } from "./vistas/DobleFactor";
import { Familias } from "./vistas/Familias";
import { NuevaContrasena } from "./vistas/NuevaContrasena";
import { Panel } from "./vistas/Panel";
import { Personal } from "./vistas/Personal";
import { Usuarios } from "./vistas/Usuarios";

const ENLACES: Enlace[] = [
  { ruta: "/", texto: t.nav_inicio },
  { ruta: "/alumnos", texto: t.nav_alumnos },
  { ruta: "/familias", texto: t.nav_familias },
  { ruta: "/personal", texto: t.nav_personal },
  { ruta: "/usuarios", texto: t.nav_usuarios },
];

export function App() {
  const [hash, setHash] = useState(window.location.hash);
  const [sesion, setSesion] = useState<Session | null | undefined>(undefined);
  const [perfil, setPerfil] = useState<Perfil | null | undefined>(undefined);
  // Llegada desde el enlace de invitación o de recuperación: primero, la contraseña nueva.
  const [pidiendoClave, setPidiendoClave] = useState(tipoEnlace);

  useEffect(() => {
    const alCambiar = () => { setHash(window.location.hash); document.getElementById("app")?.focus(); };
    window.addEventListener("hashchange", alCambiar);
    return () => window.removeEventListener("hashchange", alCambiar);
  }, []);

  useEffect(() => {
    sesionActual().then(setSesion);
    return alCambiarSesion(setSesion);
  }, []);

  useEffect(() => {
    if (!sesion) { setPerfil(sesion === null ? null : undefined); return; }
    miPerfil(sesion.user.id).then(setPerfil).catch(() => setPerfil(null));
  }, [sesion]);

  if (sesion === undefined || (sesion && perfil === undefined)) {
    return <Marco ruta="" enlaces={[]}><div className="page"><p className="en-cargando">{t.cargando}</p></div></Marco>;
  }

  if (!sesion) {
    return <Marco ruta="" enlaces={[]}><Acceso /></Marco>;
  }
  const usuario = { nombre: perfil?.nombre ?? sesion.user.email ?? "", onSalir: salir };

  if (pidiendoClave) {
    return (
      <Marco ruta="" enlaces={[]} usuario={usuario}>
        <NuevaContrasena invitacion={pidiendoClave === "invite"}
                         alTerminar={() => { setPidiendoClave(null); window.location.hash = "#/"; }} />
      </Marco>
    );
  }
  if (!perfil || !perfil.activo) {
    return <Marco ruta="" enlaces={[]} usuario={usuario}><Acceso mensaje={t.sin_perfil} /></Marco>;
  }
  // Administradores: doble factor obligatorio (aal2) antes de entrar (§3).
  if (perfil.rol === "administrador" && nivelAcceso(sesion.access_token) !== "aal2") {
    return <Marco ruta="" enlaces={[]} usuario={usuario}><DobleFactor alSalir={salir} /></Marco>;
  }

  // Ruta y permisos (src/navegacion.ts): direcciones antiguas y lo que ve cada rol.
  const ruta = leerRuta(hash, perfil.rol);
  if (aHash(ruta) !== window.location.hash) window.history.replaceState(null, "", aHash(ruta));
  const enlaces = ENLACES.filter((e) => e.ruta !== "/usuarios" || perfil.rol === "administrador");

  const vista = ruta.seccion === "/" ? <Panel perfil={perfil} />
    : ruta.seccion === "/alumnos" ? <Alumnos perfil={perfil} />
    : ruta.seccion === "/familias" ? <Familias perfil={perfil} />
    : ruta.seccion === "/personal" ? <Personal perfil={perfil} apartado={ruta.apartado ?? "encuesta"} nivel={ruta.nivel ?? "profesores"} />
    : <Usuarios perfil={perfil} />;
  return (
    <Marco ruta={ruta.seccion} enlaces={enlaces} usuario={{ nombre: perfil.nombre, onSalir: salir }}>
      <ProveedorAyuda>{vista}</ProveedorAyuda>
    </Marco>
  );
}

/** Nivel de autenticación del token (aal1 o aal2). El payload va en base64url. */
function nivelAcceso(token: string): string | null {
  try {
    const b64 = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(b64.padEnd(Math.ceil(b64.length / 4) * 4, "="))).aal ?? null;
  } catch {
    return null;
  }
}
