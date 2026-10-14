import { useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { ProveedorAyuda } from "./componentes/Ayuda";
import { Marco, Migas, type Enlace } from "./componentes/Marco";
import { alCambiarSesion, miPerfil, salir, sesionActual, type Perfil } from "./data/sesion";
import { t } from "./i18n";
import { Acceso } from "./vistas/Acceso";
import { Alumnos } from "./vistas/Alumnos";
import { Familias } from "./vistas/Familias";
import { Personal } from "./vistas/Personal";

const ENLACES: Enlace[] = [
  { ruta: "/", texto: t.nav_panel, pronto: true },
  { ruta: "/alumnos", texto: t.nav_alumnos },
  { ruta: "/familias", texto: t.nav_familias },
  { ruta: "/personal", texto: t.nav_personal },
];

function rutaActual(): string {
  const r = window.location.hash.replace(/^#/, "") || "/";
  return ENLACES.some((e) => e.ruta === r) ? r : "/";
}

export function App() {
  const [ruta, setRuta] = useState(rutaActual);
  const [sesion, setSesion] = useState<Session | null | undefined>(undefined);
  const [perfil, setPerfil] = useState<Perfil | null | undefined>(undefined);

  useEffect(() => {
    const alCambiar = () => { setRuta(rutaActual()); document.getElementById("app")?.focus(); };
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
    return <Marco ruta={ruta} enlaces={[]}><div className="page"><p className="en-cargando">{t.cargando}</p></div></Marco>;
  }

  // Sin sesión, sin perfil activo o administrador sin doble factor (llega en el paso 4).
  const aal = sesion ? nivelAcceso(sesion.access_token) : null;
  const bloqueo = !sesion ? null
    : !perfil || !perfil.activo ? t.sin_perfil
    : perfil.rol === "administrador" && aal !== "aal2" ? t.admin_mfa
    : null;
  if (!sesion || bloqueo) {
    return (
      <Marco ruta={ruta} enlaces={[]} usuario={sesion ? { nombre: perfil?.nombre ?? sesion.user.email ?? "", onSalir: salir } : undefined}>
        <Acceso mensaje={bloqueo} />
      </Marco>
    );
  }

  // La coordinación no tiene acceso a personal (§6).
  const enlaces = perfil!.rol === "coordinacion" ? ENLACES.filter((e) => e.ruta !== "/personal") : ENLACES;
  if (perfil!.rol === "coordinacion" && ruta === "/personal") window.location.hash = "#/alumnos";

  // Mientras el panel general no exista, la portada lleva a alumnos.
  const vista = ruta === "/" || ruta === "/alumnos" ? <Alumnos perfil={perfil!} />
    : ruta === "/familias" ? <Familias perfil={perfil!} />
    : ruta === "/personal" ? <Personal />
    : <Pronto ruta={ruta} />;
  return (
    <Marco ruta={ruta === "/" ? "/alumnos" : ruta} enlaces={enlaces} usuario={{ nombre: perfil!.nombre, onSalir: salir }}>
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

function Pronto({ ruta }: { ruta: string }) {
  const enlace = ENLACES.find((e) => e.ruta === ruta);
  return (
    <div className="page narrow">
      <Migas actual={enlace?.texto ?? ""} />
      <p className="eyebrow">{t.brand_title}</p>
      <h1>🚧 {enlace?.texto} <span className="r-soon">{t.proximamente}</span></h1>
      <p className="lead">{t.proximamente_d}</p>
    </div>
  );
}
