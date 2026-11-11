// Informes por persona › Tutoría y › Servicios (§7.12 y §7.13). Solo Dirección y administración (el servidor lo impone).
// En pantalla, la versión completa; los dos PDF (completo y el del destinatario). En Servicios, administración mantiene
// el responsable de cada servicio, que es quien recibe su informe.

import { useEffect, useState, type FormEvent } from "react";
import { useNavegacion } from "../componentes/Detalle";
import { TablaResumen } from "../componentes/TablaResumen";
import type { Perfil } from "../data/sesion";
import { tablasServicio, tablasTutoria } from "../data/tablasResumen";
import {
  informeServicio, informeTutoria, listarServicios, listarTutorias, ponerResponsable, quitarResponsable,
  type GrupoTutoria, type InformeServicio, type InformeTutoria, type Servicio,
} from "../data/tutoriaServicios";
import { t } from "../i18n";

const etapa = (e: string) => t.etapas[e as keyof typeof t.etapas] ?? e;

export function NivelTutoria() {
  const [grupos, setGrupos] = useState<GrupoTutoria[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const { filtro, cambiar } = useNavegacion();
  useEffect(() => { listarTutorias().then(setGrupos).catch(() => setError(t.error_datos)); }, []);
  const elegido = grupos?.find((g) => String(g.id) === filtro.grupo) ?? grupos?.[0] ?? null;

  return (
    <>
      <h2 className="section-title">{t.ipp_nivel.tutoria}</h2>
      <p className="sec-lead">{t.tut_lead}</p>
      {error && <p className="notice en-alerta en-alerta-neg" role="alert">{error}</p>}
      {grupos && (
        <div className="en-prof">
          <div className="card en-noprint">
            <ul className="en-prof-lista" aria-label={t.tut_lista}>
              {grupos.map((g) => (
                <li key={g.id}>
                  <button type="button" className={elegido?.id === g.id ? "on" : undefined} aria-pressed={elegido?.id === g.id}
                          onClick={() => cambiar({ grupo: String(g.id) })}>
                    <strong>{g.nombre}</strong>
                    <small>{g.tutor ? `${g.tutor.nombre} ${g.tutor.apellidos}` : t.tut_sin_tutor} · {etapa(g.etapa)}</small>
                  </button>
                </li>
              ))}
            </ul>
          </div>
          <div>{elegido && <InformeDeTutoria key={elegido.id} grupo={elegido} />}</div>
        </div>
      )}
    </>
  );
}

function InformeDeTutoria({ grupo }: { grupo: GrupoTutoria }) {
  const [inf, setInf] = useState<InformeTutoria | null>(null);
  const [error, setError] = useState(false);
  useEffect(() => { informeTutoria(grupo.id).then(setInf).catch(() => setError(true)); }, [grupo.id]);
  if (error) return <p className="notice en-alerta en-alerta-neg" role="alert">{t.error_datos}</p>;
  if (!inf) return <p className="en-cargando">{t.cargando}</p>;
  return (
    <>
      <div className="card">
        <p className="eyebrow">{t.tut_informe}</p>
        <h3 className="en-prof-nombre">{grupo.nombre}</h3>
        <p className="en-hint">{t.tut_tutor}: {inf.tutor ? `${inf.tutor.nombre} ${inf.tutor.apellidos}` : t.tut_sin_tutor} · {etapa(grupo.etapa)}</p>
        <p className="en-version">{t.tut_version_pantalla}</p>
        <BotonesPdf completa={async () => (await import("../pdf/generar")).descargarInformeTutoria(grupo.id, "completa")}
                    destinatario={async () => (await import("../pdf/generar")).descargarInformeTutoria(grupo.id, "tutor")}
                    textoDestinatario={t.pdf_descargar_tutor} />
      </div>
      <CuerpoTutoria inf={inf} />
    </>
  );
}

/** Tablas del informe de tutoría (también en el enlace personal y en la muestra del envío). */
export function CuerpoTutoria({ inf }: { inf: InformeTutoria }) {
  return (
    <>
      {inf.preguntas.length === 0 && <p className="notice en-alerta" style={{ marginTop: ".9rem" }}>{t.tut_sin_respuestas}</p>}
      {tablasTutoria(inf).map((x) => <TablaResumen key={x.clave} tabla={x} />)}
      <p className="notice en-alerta" style={{ marginTop: ".9rem" }}>{t.leyenda_oculto} {t.aviso_cierre}</p>
    </>
  );
}

export function NivelServicios({ perfil }: { perfil: Perfil }) {
  const [servicios, setServicios] = useState<Servicio[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const { filtro, cambiar } = useNavegacion();
  const recargar = () => listarServicios().then(setServicios).catch(() => setError(t.error_datos));
  useEffect(() => { recargar(); }, []);
  const elegido = servicios?.find((s) => String(s.id) === filtro.servicio) ?? servicios?.[0] ?? null;

  return (
    <>
      <h2 className="section-title">{t.ipp_nivel.servicios}</h2>
      <p className="sec-lead">{t.srv_lead}</p>
      {error && <p className="notice en-alerta en-alerta-neg" role="alert">{error}</p>}
      {servicios && (
        <div className="en-prof">
          <div className="card en-noprint">
            <ul className="en-prof-lista" aria-label={t.srv_lista}>
              {servicios.map((s) => (
                <li key={s.id}>
                  <button type="button" className={elegido?.id === s.id ? "on" : undefined} aria-pressed={elegido?.id === s.id}
                          onClick={() => cambiar({ servicio: String(s.id) })}>
                    <strong>{s.nombre}</strong>
                    <small>{s.responsable ? `${s.responsable.nombre} ${s.responsable.apellidos}` : t.srv_sin_responsable}</small>
                  </button>
                </li>
              ))}
            </ul>
          </div>
          <div>{elegido && <InformeDeServicio key={elegido.id} servicio={elegido} admin={perfil.rol === "administrador"} alCambiar={recargar} />}</div>
        </div>
      )}
    </>
  );
}

function InformeDeServicio({ servicio, admin, alCambiar }: { servicio: Servicio; admin: boolean; alCambiar: () => void }) {
  const [inf, setInf] = useState<InformeServicio | null>(null);
  const [error, setError] = useState(false);
  useEffect(() => { informeServicio(servicio.id).then(setInf).catch(() => setError(true)); }, [servicio.id]);
  return (
    <>
      <div className="card">
        <p className="eyebrow">{t.srv_informe}</p>
        <h3 className="en-prof-nombre">{servicio.nombre}</h3>
        <p className="en-hint">{t.srv_colectivos(servicio.colectivos.map((c) => t.srv_colectivo[c] ?? c).join(", "))}</p>
        <Responsable servicio={servicio} admin={admin} alCambiar={alCambiar} />
        <p className="en-version">{t.srv_version_pantalla}</p>
        <BotonesPdf completa={async () => (await import("../pdf/generar")).descargarInformeServicio(servicio.id, "completa")}
                    destinatario={async () => (await import("../pdf/generar")).descargarInformeServicio(servicio.id, "responsable")}
                    textoDestinatario={t.pdf_descargar_responsable} />
      </div>
      {error ? <p className="notice en-alerta en-alerta-neg" role="alert">{t.error_datos}</p>
        : !inf ? <p className="en-cargando">{t.cargando}</p> : <CuerpoServicio inf={inf} />}
    </>
  );
}

/** Tablas del informe de un servicio (también en el enlace personal y en la muestra del envío). */
export function CuerpoServicio({ inf }: { inf: InformeServicio }) {
  return (
    <>
      {tablasServicio(inf).map((x) => <TablaResumen key={x.clave} tabla={x} />)}
      <p className="notice en-alerta" style={{ marginTop: ".9rem" }}>{t.leyenda_oculto} {t.aviso_cierre}</p>
    </>
  );
}

/** Responsable del servicio: lo ven Dirección y administración; solo administración lo pone, lo cambia o lo quita. */
function Responsable({ servicio, admin, alCambiar }: { servicio: Servicio; admin: boolean; alCambiar: () => void }) {
  const r = servicio.responsable;
  const [editando, setEditando] = useState(false);
  const [seguro, setSeguro] = useState(false);
  const [datos, setDatos] = useState({ nombre: "", apellidos: "", correo: "" });
  const [estado, setEstado] = useState<"" | "guardando">("");
  const [mensaje, setMensaje] = useState<{ ok: boolean; texto: string } | null>(null);

  async function guardar(e: FormEvent) {
    e.preventDefault();
    setEstado("guardando"); setMensaje(null);
    try {
      await ponerResponsable(servicio.id, datos);
      setEditando(false); setMensaje({ ok: true, texto: t.srv_guardado }); alCambiar();
    } catch (x) { setMensaje({ ok: false, texto: (x as Error).message || t.error_datos }); }
    finally { setEstado(""); }
  }
  async function quitar() {
    setEstado("guardando"); setMensaje(null);
    try { await quitarResponsable(servicio.id); setSeguro(false); setMensaje({ ok: true, texto: t.srv_quitado }); alCambiar(); }
    catch (x) { setMensaje({ ok: false, texto: (x as Error).message || t.error_datos }); }
    finally { setEstado(""); }
  }

  return (
    <div className="en-responsable">
      <p className="en-hint"><strong>{t.srv_responsable}:</strong> {r ? `${r.nombre} ${r.apellidos}${r.correo ? ` (${r.correo})` : ""}` : t.srv_sin_responsable}</p>
      {!admin && !r && <p className="en-hint">{t.srv_resp_solo_admin}</p>}
      {admin && !editando && !seguro && (
        <p className="en-botonera en-noprint">
          <button type="button" className="btn" onClick={() => { setEditando(true); setMensaje(null); }}>{r ? t.srv_cambiar : t.srv_poner}</button>
          {r && <button type="button" className="btn" onClick={() => setSeguro(true)}>{t.srv_quitar}</button>}
        </p>
      )}
      {admin && seguro && (
        <div className="notice en-alerta en-noprint" role="alertdialog" aria-label={t.srv_quitar}>
          <p>{t.srv_quitar_seguro(servicio.nombre)}</p>
          <p className="en-botonera">
            <button type="button" className="btn primary" onClick={quitar} disabled={estado !== ""}>{t.srv_quitar}</button>
            <button type="button" className="btn" onClick={() => setSeguro(false)} disabled={estado !== ""}>{t.env_cancelar}</button>
          </p>
        </div>
      )}
      {admin && editando && (
        <form className="en-form-responsable en-noprint" onSubmit={guardar} aria-label={t.srv_resp_titulo}>
          <p className="en-hint">{t.srv_resp_ayuda}</p>
          <label><span>{t.srv_correo}</span>
            <input type="email" className="en-input" required value={datos.correo} onChange={(e) => setDatos({ ...datos, correo: e.target.value })} /></label>
          <label><span>{t.srv_nombre}</span>
            <input className="en-input" value={datos.nombre} onChange={(e) => setDatos({ ...datos, nombre: e.target.value })} /></label>
          <label><span>{t.srv_apellidos}</span>
            <input className="en-input" value={datos.apellidos} onChange={(e) => setDatos({ ...datos, apellidos: e.target.value })} /></label>
          <p className="en-botonera">
            <button type="submit" className="btn primary" disabled={estado !== ""}>{t.srv_guardar}</button>
            <button type="button" className="btn" onClick={() => setEditando(false)} disabled={estado !== ""}>{t.env_cancelar}</button>
          </p>
        </form>
      )}
      {mensaje && <p className={`notice en-alerta${mensaje.ok ? " en-alerta-pos" : " en-alerta-neg"}`} role="status">{mensaje.texto}</p>}
    </div>
  );
}

/** «Descargar PDF completo» (Dirección y administración) y el PDF de la versión del destinatario. */
function BotonesPdf({ completa, destinatario, textoDestinatario }: {
  completa: () => Promise<void>; destinatario: () => Promise<void>; textoDestinatario: string;
}) {
  const [estado, setEstado] = useState<"" | "generando" | "error">("");
  async function pulsar(fn: () => Promise<void>) {
    setEstado("generando");
    try { await fn(); setEstado(""); } catch { setEstado("error"); }
  }
  return (
    <p className="en-noprint en-botonera">
      <button type="button" className="btn primary" onClick={() => pulsar(completa)} disabled={estado === "generando"}>
        📄 {estado === "generando" ? t.pdf_generando : t.pdf_descargar_completa}
      </button>
      <button type="button" className="btn" onClick={() => pulsar(destinatario)} disabled={estado === "generando"}>📄 {textoDestinatario}</button>
      {estado === "error" && <span className="en-error" role="alert"> {t.pdf_error}</span>}
    </p>
  );
}
