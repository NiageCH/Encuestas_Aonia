// Página del enlace personal (§7.10): se abre sin cuenta, con el token del correo. Al docente le enseña la versión docente
// de su informe y a la jefatura la versión para la jefatura (las dos con el mínimo de 5 y la complementaria), con el PDF. Cada apertura y cada descarga quedan registradas en
// el servidor. Si el enlace ha caducado o no vale, lo dice y remite a Dirección.

import { useEffect, useRef, useState } from "react";
import { Barra } from "../componentes/Graficos";
import { Oculto } from "../componentes/Oculto";
import { informeEnlace, type InformeEnlace } from "../data/envio";
import type { InformeEquipo, InformeJefe, InformeProfesor } from "../data/resultados";
import { etiquetaClase, ordenarClases, textoAlumnos, tituloAlumnosJefe, tituloEquipo, tituloReuniones } from "../etiquetas";
import * as f from "../formato";
import { t } from "../i18n";

export function InformeEnlacePagina({ token }: { token: string }) {
  const [datos, setDatos] = useState<InformeEnlace | null>(null);
  const [error, setError] = useState(false);

  // Una sola petición por visita (cada una cuenta como apertura), también con el doble montaje de React en desarrollo.
  const pedido = useRef("");
  useEffect(() => {
    if (pedido.current === token) return;
    pedido.current = token;
    informeEnlace(token).then(setDatos).catch(() => setError(true));
  }, [token]);

  if (error || datos?.estado === "no_valido") return <div className="page"><h1>{t.enl_titulo}</h1><p className="notice en-alerta">{t.enl_no_valido}</p></div>;
  if (datos?.estado === "limitado") return <div className="page"><h1>{t.enl_titulo}</h1><p className="notice en-alerta">{t.enl_limitado}</p></div>;
  if (!datos) return <div className="page"><p className="en-cargando">{t.cargando}</p></div>;
  if (datos.estado === "caducado") {
    return <div className="page"><h1>{t.enl_titulo}</h1><p className="notice en-alerta">{t.enl_caducado(fechaHora(datos.caduca))}</p></div>;
  }

  if (datos.tipo !== "profesor") return <PaginaJefatura token={token} datos={datos} />;
  return <PaginaProfesor token={token} caduca={datos.caduca} profesor={datos.profesor} informe={datos.informe} />;
}

type Persona = { nombre: string; apellidos: string; departamento: string | null };

function PaginaProfesor({ token, caduca, profesor, informe }: { token: string; caduca: string; profesor: Persona; informe: InformeProfesor }) {
  const [pdf, setPdf] = useState<"" | "generando" | "error">("");
  const g = informe.global;
  const celdas = ordenarClases(informe.celdas);
  const propias = celdas.filter((c) => c.tipo !== "compartida");
  const compartidas = celdas.filter((c) => c.tipo === "compartida");
  const etapas = Object.keys(informe.comparacion).filter((k) => k !== "colegio");

  async function descargar() {
    setPdf("generando");
    try {
      const { descargarInformeEnlace } = await import("../pdf/generar");
      await descargarInformeEnlace(token, profesor, informe);
      setPdf("");
    } catch { setPdf("error"); }
  }

  return (
    <div className="page en-informe">
      <p className="eyebrow">{t.prof_informe}</p>
      <h1>{profesor.nombre} {profesor.apellidos}</h1>
      {profesor.departamento && <p className="en-hint">{t.prof_departamento}: {profesor.departamento}</p>}
      <p className="en-version">{t.version_docente}</p>
      <p className="lead">{t.enl_lead(fechaHora(caduca))}</p>
      <p className="en-botonera">
        <button type="button" className="btn primary" onClick={descargar} disabled={pdf === "generando"}>
          📄 {pdf === "generando" ? t.pdf_generando : t.enl_descargar}
        </button>
        {pdf === "error" && <span className="en-error" role="alert"> {t.pdf_error}</span>}
      </p>

      <div className="en-kpis en-kpis3">
        <div className="card en-kpi hl">
          <div className="l">{t.prof_media_global}</div>
          <div className="v">{g.suprimido ? <span className="en-oculto">{t.prof_sin_visibles}</span> : <>{f.media(g.media!)} <small>/ 6</small></>}</div>
          <div className="d">{g.suprimido ? "" : t.prof_global_d(g.combinaciones!, f.recuento(g.n_valoraciones!))}</div>
        </div>
        {etapas.map((e) => (
          <div key={e} className="card en-kpi">
            <div className="l">{t.prof_media_etapa(t.etapas[e as keyof typeof t.etapas])}</div>
            <div className="v">{informe.comparacion[e].suprimido ? <Oculto fila={informe.comparacion[e]} /> : <>{f.media(informe.comparacion[e].media!)} <small>/ 6</small></>}</div>
          </div>
        ))}
        {informe.comparacion.colegio && (
          <div className="card en-kpi">
            <div className="l">{t.prof_media_colegio}</div>
            <div className="v">{informe.comparacion.colegio.suprimido ? <Oculto fila={informe.comparacion.colegio} /> : <>{f.media(informe.comparacion.colegio.media!)} <small>/ 6</small></>}</div>
          </div>
        )}
      </div>
      {informe.combinaciones_excluidas > 0 && <p className="notice en-alerta" style={{ marginTop: ".9rem" }}>{t.prof_excluidas(informe.combinaciones_excluidas)}</p>}

      <div className="card" style={{ marginTop: ".9rem" }}>
        <h3>{t.prof_por_asignatura}</h3>
        <p className="en-hint">{t.prof_por_asignatura_lead}</p>
        {propias.length === 0 ? <p className="en-hint">{compartidas.length ? t.prof_sin_propias : t.sin_datos_seccion}</p>
          : propias.map((c) => <Barra key={`${c.clave.cuestionario}-${c.clave.grupo}-${c.clave.asignatura}`} etiqueta={etiquetaClase(c)} fila={c} />)}
      </div>
      {compartidas.length > 0 && (
        <div className="card" style={{ marginTop: ".9rem" }}>
          <h3>{t.prof_compartidas}</h3>
          <p className="notice en-alerta">{t.prof_compartidas_nota}</p>
          {compartidas.map((c) => <Barra key={`${c.clave.cuestionario}-${c.clave.grupo}-${c.clave.asignatura}`} etiqueta={etiquetaClase(c)} fila={c} />)}
        </div>
      )}
      <p className="notice en-alerta" style={{ marginTop: ".9rem" }}>{t.leyenda_oculto} {t.aviso_cierre}</p>
      <p className="en-hint">{t.enl_pie}</p>
    </div>
  );
}

/** Jefatura de departamento o del Equipo de Individuación: medias de cada sección y el PDF (versión para la jefatura). */
function PaginaJefatura({ token, datos }: { token: string; datos: Extract<InformeEnlace, { estado: "ok" }> }) {
  const [pdf, setPdf] = useState<"" | "generando" | "error">("");
  const nombre = `${datos.profesor.nombre} ${datos.profesor.apellidos}`;
  const dep = datos.tipo === "jefatura_departamento" ? (datos.informe as InformeJefe) : null;
  const eq = datos.tipo === "jefatura_equipo" ? (datos.informe as InformeEquipo) : null;
  const secciones = dep ? dep.reuniones.map((r) => ({ titulo: tituloReuniones(r), total: r.total }))
    : [{ titulo: `${t.resp_equipo}: ${tituloEquipo(eq!.tramos)}`, total: eq!.total }];

  async function descargar() {
    setPdf("generando");
    try {
      const g = await import("../pdf/generar");
      const d = dep ? g.datosJefe(dep, nombre) : g.datosEquipo(eq!);
      await g.descargarJefaturaEnlace(token, nombre, d, dep ? `Departamentos_${datos.profesor.apellidos}_${datos.profesor.nombre}` : `Equipo_Individuacion_${eq!.tramos.join("_")}`);
      setPdf("");
    } catch { setPdf("error"); }
  }

  return (
    <div className="page en-informe">
      <p className="eyebrow">{t.resp_informe}</p>
      <h1>{nombre}</h1>
      <p className="en-hint">{dep ? t.jefe_departamentos(dep.departamentos) : t.resp_equipo}</p>
      <p className="en-version">{t.version_jefatura}</p>
      <p className="lead">{t.enl_lead_jefatura(fechaHora(datos.caduca))}</p>
      <p className="en-botonera">
        <button type="button" className="btn primary" onClick={descargar} disabled={pdf === "generando"}>
          📄 {pdf === "generando" ? t.pdf_generando : t.enl_descargar}
        </button>
        {pdf === "error" && <span className="en-error" role="alert"> {t.pdf_error}</span>}
      </p>
      <div className="en-kpis en-kpis3">
        {secciones.map((x) => (
          <div key={x.titulo} className="card en-kpi">
            <div className="l">{x.titulo}</div>
            <div className="v">{x.total.suprimido ? <Oculto fila={x.total} /> : <>{f.media(x.total.media!)} <small>/ 6</small></>}</div>
            <div className="d">{x.total.suprimido ? "" : t.tip_personas(f.recuento(x.total.n!))}</div>
          </div>
        ))}
        {dep && (
          <div className="card en-kpi">
            <div className="l">{tituloAlumnosJefe(dep.alumnos.departamentos)}</div>
            <div className="v">{textoAlumnos(dep.alumnos.media).texto}</div>
            <div className="d">{textoAlumnos(dep.alumnos.media).detalle ?? ""}</div>
          </div>
        )}
      </div>
      {dep && dep.reuniones.length === 0 && <p className="notice en-alerta" style={{ marginTop: ".9rem" }}>{t.jefe_sin_reuniones}</p>}
      <p className="notice en-alerta" style={{ marginTop: ".9rem" }}>{t.enl_jefatura_pdf} {t.leyenda_oculto}</p>
      <p className="en-hint">{t.enl_pie}</p>
    </div>
  );
}

function fechaHora(iso: string) {
  return new Date(iso).toLocaleString("es-ES", { timeZone: "Europe/Madrid", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
}
