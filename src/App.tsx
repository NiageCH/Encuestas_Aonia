import { useEffect, useRef, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { ProveedorAyuda } from "./componentes/Ayuda";
import { ProveedorNavegacion } from "./componentes/Detalle";
import { Migas } from "./componentes/Marco";
import { ProveedorCargados, SinResultados } from "./componentes/SinResultados";
import { estadoDeError, hayResultados, nivelAcceso, puedeVerResultados, type EstadoCarga } from "./acceso";
import { Marco, type Enlace } from "./componentes/Marco";
import { tipoEnlace } from "./data/cliente";
import { alCambiarSesion, mfaAdminObligatorio, miPerfil, salir, sesionActual, type Perfil } from "./data/sesion";
import { colectivosCargados, type Colectivo } from "./data/resultados";
import { t } from "./i18n";
import { aHash, leerRuta, menu, type Seccion } from "./navegacion";
import { Acceso } from "./vistas/Acceso";
import { InformeEnlacePagina } from "./vistas/InformeEnlace";
import { Abiertas } from "./vistas/Abiertas";
import { Alumnos } from "./vistas/Alumnos";
import { DobleFactor } from "./vistas/DobleFactor";
import { Familias } from "./vistas/Familias";
import { InformesPorPersona } from "./vistas/InformesPorPersona";
import { NuevaContrasena } from "./vistas/NuevaContrasena";
import { Panel } from "./vistas/Panel";
import { Personal } from "./vistas/Personal";
import { Usuarios } from "./vistas/Usuarios";

const TEXTO_MENU: Record<Seccion, string> = {
  "/": t.nav_inicio, "/alumnos": t.nav_alumnos, "/familias": t.nav_familias, "/personal": t.nav_personal,
  "/informes": t.nav_informes, "/abiertas": t.nav_abiertas, "/usuarios": t.nav_usuarios,
};

export function App() {
  const [hash, setHash] = useState(window.location.hash);
  const [sesion, setSesion] = useState<Session | null | undefined>(undefined);
  const [perfil, setPerfil] = useState<Perfil | null | undefined>(undefined);
  // Llegada desde el enlace de invitación o de recuperación: primero, la contraseña nueva.
  const [pidiendoClave, setPidiendoClave] = useState(tipoEnlace);
  const [mfaObligatorio, setMfaObligatorio] = useState<boolean | undefined>(undefined);
  const [cargados, setCargados] = useState<EstadoCarga>({ estado: "cargando" });

  // El foco vuelve arriba al cambiar de pantalla; no al cambiar solo un filtro de la misma pantalla.
  const pantalla = useRef(window.location.hash.split("?")[0]);
  useEffect(() => {
    const alCambiar = () => {
      setHash(window.location.hash);
      const nueva = window.location.hash.split("?")[0];
      if (nueva !== pantalla.current) document.getElementById("app")?.focus();
      pantalla.current = nueva;
    };
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
    mfaAdminObligatorio().then(setMfaObligatorio);
  }, [sesion]);

  // Colectivos con resultados cargados en el curso (estado vacío de las pantallas). Solo cuando la sesión puede ver
  // resultados: un administrador, después del doble factor. Se vuelve a preguntar cuando eso cambia (al pasar el código);
  // antes se preguntaba con la sesión todavía sin verificar y la respuesta vacía se quedaba como «no hay resultados».
  const listo = puedeVerResultados(perfil?.rol, perfil?.activo, mfaObligatorio, nivelAcceso(sesion?.access_token));
  useEffect(() => {
    if (!listo) { setCargados({ estado: "cargando" }); return; }
    let vigente = true;
    colectivosCargados()
      .then((c) => vigente && setCargados({ estado: "listo", colectivos: c }))
      .catch((e) => vigente && setCargados(estadoDeError(e)));
    return () => { vigente = false; };
  }, [listo, sesion?.user.id]);

  // Enlace personal de un docente (§7.10): sin cuenta, antes de cualquier comprobación de sesión.
  const enlace = /^#\/informe\/([A-Za-z0-9_-]{40,})$/.exec(hash);
  if (enlace) {
    return <Marco ruta="" enlaces={[]}><ProveedorAyuda><InformeEnlacePagina token={enlace[1]} /></ProveedorAyuda></Marco>;
  }

  if (sesion === undefined || (sesion && (perfil === undefined || mfaObligatorio === undefined))) {
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
  // Solo en el entorno local de desarrollo puede estar desactivado (docs/DESPLIEGUE.md).
  if (perfil.rol === "administrador" && mfaObligatorio !== false && nivelAcceso(sesion.access_token) !== "aal2") {
    return <Marco ruta="" enlaces={[]} usuario={usuario}><DobleFactor alSalir={salir} /></Marco>;
  }

  // Ruta y permisos (src/navegacion.ts): direcciones antiguas y lo que ve cada rol.
  const ruta = leerRuta(hash, perfil.rol);
  if (aHash(ruta) !== window.location.hash) window.history.replaceState(null, "", aHash(ruta));
  const enlaces: Enlace[] = menu(perfil.rol).map((s) => ({ ruta: s, texto: TEXTO_MENU[s] }));

  const visibles: Colectivo[] = perfil.rol === "coordinacion" ? ["alumnos", "familias"] : ["alumnos", "familias", "personal"];
  const hay = (...c: Colectivo[]) => hayResultados(cargados, c);
  const vacia = (titulo: string, colectivo?: Colectivo) => (
    <div className="page"><Migas actual={titulo} /><h1>{titulo}</h1><SinResultados colectivo={colectivo} /></div>
  );
  const vista = ruta.seccion === "/" ? (hay(...visibles) ? <Panel perfil={perfil} /> : vacia(t.nav_inicio))
    : ruta.seccion === "/alumnos" ? (hay("alumnos") ? <Alumnos perfil={perfil} /> : vacia(t.nav_alumnos, "alumnos"))
    : ruta.seccion === "/familias" ? (hay("familias") ? <Familias perfil={perfil} /> : vacia(t.nav_familias, "familias"))
    : ruta.seccion === "/personal" ? <Personal />
    : ruta.seccion === "/abiertas" ? <Abiertas />
    : ruta.seccion === "/informes" ? <InformesPorPersona perfil={perfil} nivel={ruta.nivel ?? "profesores"} />
    : <Usuarios perfil={perfil} descargas={!!ruta.descargas} />;
  return (
    <Marco ruta={ruta.seccion} enlaces={enlaces} usuario={{ nombre: perfil.nombre, onSalir: salir }}>
      {perfil.rol === "administrador" && mfaObligatorio === false && <p className="en-aviso-entorno" role="note">{t.mfa_desactivado_local}</p>}
      <ProveedorCargados cargados={cargados}><ProveedorNavegacion ruta={ruta} rol={perfil.rol}><ProveedorAyuda>{vista}</ProveedorAyuda></ProveedorNavegacion></ProveedorCargados>
    </Marco>
  );
}
