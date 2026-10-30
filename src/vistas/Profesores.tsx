// Informe por profesor (§7.2 y §7.0), dentro de Personal → Informes por persona: lo que opinan
// los alumnos de cada docente. Buscador, «Sus clases» (único docente o alumnos que escribieron su
// nombre; de ahí sale la media global) y «Valoraciones compartidas» (varios docentes), con el
// mínimo de 5 y la complementaria, comparación con su etapa y el colegio, y detalle por pregunta.

import { useEffect, useMemo, useRef, useState } from "react";
import { useAyuda } from "../componentes/Ayuda";
import { Barra } from "../componentes/Graficos";
import { BandaDetalle, useBajarA, useNavegacion } from "../componentes/Detalle";
import type { Perfil } from "../data/sesion";
import { MarcaMenos5, Oculto } from "../componentes/Oculto";
import {
  listarProfesores, preguntasProfesorado, profesoresDeClase, resultadosProfesor,
  type CeldaProfesor, type PreguntaBloque, type Profesor, type ResultadoProfesor, type VersionInforme,
} from "../data/resultados";
import { claveClase, enumerar, etiquetaClase, ordenarClases } from "../etiquetas";
import * as f from "../formato";
import { t } from "../i18n";
import { leyendaAnonimato, veMenos5 } from "../criterio";

export function InformesProfesor({ perfil }: { perfil: Perfil }) {
  const [lista, setLista] = useState<Profesor[] | null>(null);
  const [busqueda, setBusqueda] = useState("");
  const [error, setError] = useState<string | null>(null);
  // Filtros del detalle (desde Alumnado o desde un informe de jefatura) y docente elegido, en la dirección.
  const { filtro, cambiar } = useNavegacion();
  const elegido = lista?.find((p) => String(p.id) === filtro.profesor) ?? null;
  const setElegido = (p: Profesor) => cambiar({ profesor: String(p.id) });
  const departamentos = filtro.departamento ? filtro.departamento.split("|") : null;
  const [deClase, setDeClase] = useState<number[] | null>(null);

  useEffect(() => { listarProfesores().then(setLista).catch(() => setError(t.error_datos)); }, []);
  useEffect(() => {
    setDeClase(null);
    if (!filtro.asignatura || !filtro.cuestionario) return;
    profesoresDeClase({ cuestionario: filtro.cuestionario, asignatura: filtro.asignatura, ...(filtro.grupo ? { grupo: filtro.grupo } : {}) })
      .then(setDeClase).catch(() => setError(t.error_datos));
  }, [filtro.asignatura, filtro.cuestionario, filtro.grupo]);

  // La lista que queda con el filtro del detalle (o toda): de ella salen la búsqueda y el lote.
  const delFiltro = useMemo(() => (lista ?? []).filter((p) =>
    (!departamentos || departamentos.includes(p.departamento ?? ""))
    && (!filtro.asignatura || (deClase ?? []).includes(p.id))), [lista, filtro.departamento, filtro.asignatura, deClase]);
  const conFiltro = !!departamentos || !!filtro.asignatura;
  const filtrados = useMemo(() => {
    const q = normal(busqueda);
    return delFiltro.filter((p) => !q || normal(`${p.nombre} ${p.apellidos} ${p.departamento ?? ""}`).includes(q));
  }, [delFiltro, busqueda]);

  return (
    <section>
      <h2 className="section-title">{t.prof_titulo}</h2>
      <p className="sec-lead">{perfil.rol === "coordinacion" ? t.prof_lead_coord : t.prof_lead}</p>
      {error && <p className="notice en-alerta en-alerta-neg" role="alert">{error}</p>}
      {lista && lista.length === 0 && <p className="notice en-alerta">{t.prof_sin_profesores}</p>}
      <BandaDetalle partes={[
        ...(filtro.asignatura ? [[t.det_asignatura, filtro.asignatura] as [string, string]] : []),
        ...(filtro.grupo ? [[t.exp_grupo, filtro.grupo] as [string, string]] : []),
        ...(departamentos ? [[t.det_departamento, enumerar(departamentos)] as [string, string]] : []),
      ]} quitar={{ asignatura: null, cuestionario: null, grupo: null, departamento: null }} />
      {lista && lista.length > 0 && (
        <div className="en-prof">
          <div className="card en-prof-buscador en-noprint">
            <label className="en-filters" style={{ display: "grid" }}>
              <span>{t.prof_buscar}</span>
              <input type="search" className="en-input" value={busqueda} onChange={(e) => setBusqueda(e.target.value)}
                     placeholder={t.prof_buscar_ph} autoComplete="off" />
            </label>
            {conFiltro && <p className="en-hint" role="status">{t.det_lista_filtrada(delFiltro.length)}</p>}
            <ul className="en-prof-lista" aria-label={t.prof_lista}>
              {filtrados.slice(0, 60).map((p) => (
                <li key={p.id}>
                  <button type="button" className={elegido?.id === p.id ? "on" : undefined} aria-pressed={elegido?.id === p.id}
                          onClick={() => setElegido(p)}>
                    <strong>{p.apellidos}, {p.nombre}{p.situacion === "baja" && <small> · {t.prof_baja}</small>}</strong>
                    {p.departamento && <small>{p.departamento}</small>}
                  </button>
                </li>
              ))}
            </ul>
            {filtrados.length > 60 && <p className="en-hint">{t.prof_mas(filtrados.length - 60)}</p>}
            <Lote profesores={conFiltro ? delFiltro : lista} completa={veMenos5(perfil.rol)} />
          </div>
          <div>{elegido ? <Informe profesor={elegido} perfil={perfil} /> : <p className="en-hint">{t.prof_elige}</p>}</div>
        </div>
      )}
    </section>
  );
}

function normal(s: string) {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
}

function Informe({ profesor, perfil }: { profesor: Profesor; perfil: Perfil }) {
  const completa = veMenos5(perfil.rol);
  const ayuda = useAyuda();
  const { filtro, aqui } = useNavegacion();
  const [datos, setDatos] = useState<ResultadoProfesor | null>(null);
  const [preguntas, setPreguntas] = useState<{ p: PreguntaBloque; r: ResultadoProfesor }[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let vigente = true;
    setDatos(null); setPreguntas(null); setError(null);
    (async () => {
      const r = await resultadosProfesor(profesor.id);
      if (!vigente) return;
      setDatos(r);
      const cuestionarios = [...new Set(r.celdas.map((c) => c.clave.cuestionario))];
      const ps = cuestionarios.length ? await preguntasProfesorado(cuestionarios) : [];
      const rs = await Promise.all(ps.map((p) => resultadosProfesor(profesor.id, { tipo: "pregunta", codigo: p.codigo })));
      if (vigente) setPreguntas(ps.map((p, i) => ({ p, r: rs[i] })));
    })().catch(() => vigente && setError(t.error_datos));
    return () => { vigente = false; };
  }, [profesor.id]);

  useBajarA(!!preguntas);
  if (error) return <p className="notice en-alerta en-alerta-neg" role="alert">{error}</p>;
  if (!datos) return <p className="en-cargando">{t.cargando}</p>;

  // Versión completa: cada clase lleva a su detalle pregunta por pregunta (la versión docente no lo tiene).
  const aClase = (c: CeldaProfesor) => (completa ? aqui({ clase: claveClase(c), ver: "en-por-clase" }) : undefined);
  const etapas = Object.keys(datos.comparacion).filter((k) => k !== "colegio");
  const g = datos.global;
  const celdas = ordenarClases(datos.celdas);
  const propias = celdas.filter((c) => c.tipo !== "compartida");
  const compartidas = celdas.filter((c) => c.tipo === "compartida");

  return (
    <div className="en-informe">
      <div className="card">
        <p className="eyebrow">{t.prof_informe}</p>
        <h3 className="en-prof-nombre">{profesor.nombre} {profesor.apellidos}</h3>
        {profesor.departamento && <p className="en-hint">{t.prof_departamento}: {profesor.departamento}</p>}
        {completa && <p className="en-version">{t.prof_version_completa_pantalla}</p>}
        <BotonPdf profesor={profesor} completa={completa} />
        <div className="en-kpis en-kpis3">
          <div className="card en-kpi hl en-con-ayuda" {...ayuda([t.prof_media_global, t.prof_media_global_tip])}>
            <div className="l">{t.prof_media_global}</div>
            <div className="v">{g.suprimido ? <span className="en-oculto">{t.prof_sin_visibles}</span> : <>{f.media(g.media!)} <small>/ 6</small></>}</div>
            <div className="d">
              {g.suprimido ? "" : t.prof_global_d(g.combinaciones!, f.recuento(g.n_valoraciones!))}
              {g.menos_de_5 ? <><br />{t.prof_global_menos5(g.menos_de_5)} <MarcaMenos5 fila={{ menos_de_5: true }} /></> : null}
              {datos.global_docente && g.menos_de_5 ? <><br />{t.prof_global_docente(datos.global_docente.suprimido ? t.prof_sin_visibles : f.media(datos.global_docente.media!))}</> : null}
            </div>
          </div>
          {etapas.map((e) => (
            <div key={e} className="card en-kpi en-con-ayuda" {...ayuda([t.prof_media_etapa(t.etapas[e as keyof typeof t.etapas]), t.prof_comparacion_tip])}>
              <div className="l">{t.prof_media_etapa(t.etapas[e as keyof typeof t.etapas])}</div>
              <div className="v">{datos.comparacion[e].suprimido ? <Oculto fila={datos.comparacion[e]} /> : <>{f.media(datos.comparacion[e].media!)} <small>/ 6</small></>}</div>
            </div>
          ))}
          {datos.comparacion.colegio && (
            <div className="card en-kpi en-con-ayuda" {...ayuda([t.prof_media_colegio, t.prof_comparacion_tip])}>
              <div className="l">{t.prof_media_colegio}</div>
              <div className="v">{datos.comparacion.colegio.suprimido ? <Oculto fila={datos.comparacion.colegio} /> : <>{f.media(datos.comparacion.colegio.media!)} <small>/ 6</small></>}</div>
            </div>
          )}
        </div>
        {datos.combinaciones_excluidas > 0 && <p className="notice en-alerta" style={{ marginTop: ".9rem" }}>{t.prof_excluidas(datos.combinaciones_excluidas)}</p>}
      </div>

      <div className="card" style={{ marginTop: ".9rem" }}>
        <h3>{t.prof_por_asignatura}</h3>
        <p className="en-hint">{t.prof_por_asignatura_lead}</p>
        {propias.length === 0 ? <p className="en-hint">{compartidas.length ? t.prof_sin_propias : t.sin_datos_seccion}</p>
          : propias.map((c) => <Barra key={`${c.clave.cuestionario}-${c.clave.grupo}-${c.clave.asignatura}`} etiqueta={etiquetaClase(c)} fila={c} destino={aClase(c)} />)}
      </div>

      {compartidas.length > 0 && (
        <div className="card" style={{ marginTop: ".9rem" }}>
          <h3>{t.prof_compartidas}</h3>
          <p className="notice en-alerta">{t.prof_compartidas_nota}</p>
          {compartidas.map((c) => <Barra key={`${c.clave.cuestionario}-${c.clave.grupo}-${c.clave.asignatura}`} etiqueta={etiquetaClase(c)} fila={c} destino={aClase(c)} />)}
        </div>
      )}

      <div className="card" style={{ marginTop: ".9rem" }}>
        <h3>{t.prof_detalle}</h3>
        <p className="en-hint">{t.prof_detalle_lead}</p>
        {!preguntas ? <p className="en-cargando">{t.cargando}</p> : (
          <div className="tbl-wrap">
            <table className="doc-table en-tabla-prof">
              <thead>
                <tr>
                  <th>{t.pregunta}</th><th>{t.prof_col_profesor}</th>
                  {etapas.map((e) => <th key={e}>{t.etapas[e as keyof typeof t.etapas]}</th>)}
                  {datos.comparacion.colegio && <th>{t.prof_col_colegio}</th>}
                </tr>
              </thead>
              <tbody>
                {preguntas.map(({ p, r }) => (
                  <tr key={p.codigo}>
                    <td>{p.texto}</td>
                    <td className="n en-con-ayuda" data-etiqueta={t.prof_col_profesor} {...ayuda(r.global.suprimido ? [p.texto, t.prof_sin_visibles]
                      : [p.texto, t.tip_media(f.media(r.global.media!)), t.tip_valoraciones(f.recuento(r.global.n_valoraciones!))])}>
                      {r.global.suprimido ? <span className="en-oculto">{t.oculto_menos5}</span> : <strong>{f.media(r.global.media!)}</strong>}
                      {!r.global.suprimido && r.global.menos_de_5 ? <MarcaMenos5 fila={{ menos_de_5: true }} /> : null}
                    </td>
                    {etapas.map((e) => <td key={e} className="n" data-etiqueta={t.etapas[e as keyof typeof t.etapas]}>{celda(r.comparacion[e])}</td>)}
                    {datos.comparacion.colegio && <td className="n" data-etiqueta={t.prof_col_colegio}>{celda(r.comparacion.colegio)}</td>}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
      {completa && preguntas && <DetallePorClase celdas={celdas} preguntas={preguntas} abierta={filtro.clase} />}
      <p className="notice en-alerta" style={{ marginTop: ".9rem" }}>{leyendaAnonimato(perfil.rol)}</p>
    </div>
  );

  function celda(fila?: ResultadoProfesor["comparacion"][string]) {
    if (!fila) return "";
    return fila.suprimido ? <Oculto fila={fila} /> : f.media(fila.media!);
  }
}

/** Versión completa (Dirección y administración): cada pregunta en cada clase, con la marca «menos de 5». */
function DetallePorClase({ celdas, preguntas, abierta }: {
  celdas: CeldaProfesor[]; preguntas: { p: PreguntaBloque; r: ResultadoProfesor }[]; abierta?: string;
}) {
  const mismaClase = (a: CeldaProfesor, b: CeldaProfesor) =>
    a.clave.cuestionario === b.clave.cuestionario && a.clave.grupo === b.clave.grupo && a.clave.asignatura === b.clave.asignatura;
  return (
    <div className="card" id="en-por-clase" style={{ marginTop: ".9rem" }}>
      <h3>{t.prof_por_clase}</h3>
      <p className="en-hint">{t.prof_por_clase_lead}</p>
      {celdas.map((c) => (
        <details key={`${c.clave.cuestionario}-${c.clave.grupo}-${c.clave.asignatura}`} id={`en-clase-${claveClase(c)}`}
                 className={`en-clase-detalle${abierta === claveClase(c) ? " en-destacado" : ""}`} open={abierta === claveClase(c) || undefined}>
          <summary>
            <strong>{etiquetaClase(c)}</strong>
            {c.tipo === "compartida" && <small> · {t.prof_compartida_corto}</small>}
            {" · "}{c.suprimido ? <Oculto fila={c} /> : <>{f.media(c.media!)} · n {f.recuento(c.n!)}</>}
            <MarcaMenos5 fila={c} />
          </summary>
          <div className="tbl-wrap">
            <table className="doc-table en-tabla-prof">
              <thead><tr><th>{t.pregunta}</th><th>{t.media}</th><th>n</th></tr></thead>
              <tbody>
                {preguntas.filter(({ r }) => r.celdas.some((y) => mismaClase(y, c))).map(({ p, r }) => {
                  const x = r.celdas.find((y) => mismaClase(y, c));
                  return (
                    <tr key={p.codigo}>
                      <td>{p.texto}</td>
                      <td className="n" data-etiqueta={t.media}>{!x ? "·" : x.suprimido ? <Oculto fila={x} /> : <strong>{f.media(x.media!)}</strong>}</td>
                      <td className="n" data-etiqueta="n">{x && !x.suprimido ? <>{f.recuento(x.n!)}<MarcaMenos5 fila={x} /></> : ""}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </details>
      ))}
    </div>
  );
}

function BotonPdf({ profesor, completa }: { profesor: Profesor; completa: boolean }) {
  const [estado, setEstado] = useState<"" | "generando" | "error">("");
  async function generar(version: VersionInforme) {
    setEstado("generando");
    try {
      const { descargarInforme } = await import("../pdf/generar");
      await descargarInforme(profesor, version);
      setEstado("");
    } catch {
      setEstado("error");
    }
  }
  return (
    <p className="en-noprint en-botonera">
      <button type="button" className="btn primary" onClick={() => generar(completa ? "completa" : "docente")} disabled={estado === "generando"}>
        📄 {estado === "generando" ? t.pdf_generando : completa ? t.pdf_descargar_completa : t.pdf_descargar}
      </button>
      {completa && (
        <button type="button" className="btn" onClick={() => generar("docente")} disabled={estado === "generando"}>
          📄 {t.pdf_descargar_docente}
        </button>
      )}
      {estado === "error" && <span className="en-error" role="alert"> {t.pdf_error}</span>}
    </p>
  );
}

function Lote({ profesores, completa }: { profesores: Profesor[]; completa: boolean }) {
  const [version, setVersion] = useState<VersionInforme>(completa ? "completa" : "docente");
  const [progreso, setProgreso] = useState<[number, number, "datos" | "pdf"] | null>(null);
  const [mensaje, setMensaje] = useState<string | null>(null);
  const cancelar = useRef(false);
  async function generar() {
    cancelar.current = false;
    setMensaje(null);
    setProgreso([0, profesores.length, "datos"]);
    try {
      const { descargarLote } = await import("../pdf/generar");
      const hechos = await descargarLote(profesores, version, (n, total, fase) => setProgreso([n, total, fase]), () => cancelar.current);
      setMensaje(hechos > 0 ? t.pdf_lote_hecho(hechos) : null);
    } catch {
      setMensaje(t.pdf_error);
    } finally {
      setProgreso(null);
    }
  }
  return (
    <div className="en-lote">
      {progreso ? (
        <>
          <p className="en-hint" role="status">{progreso[2] === "datos" ? t.pdf_lote_preparando(progreso[0], progreso[1]) : t.pdf_lote_progreso(progreso[0], progreso[1])}</p>
          <progress max={progreso[1]} value={progreso[0]} />
          {progreso[2] === "datos" && <button type="button" className="btn" onClick={() => { cancelar.current = true; }}>{t.pdf_lote_cancelar}</button>}
        </>
      ) : (
        <>
          {completa && (
            <fieldset className="en-version-lote">
              <legend>{t.pdf_lote_version}</legend>
              {(["completa", "docente"] as const).map((v) => (
                <label key={v}><input type="radio" name="version-lote" checked={version === v} onChange={() => setVersion(v)} />
                  {v === "completa" ? t.version_completa : t.version_docente}</label>
              ))}
            </fieldset>
          )}
          <button type="button" className="btn" onClick={generar}>🗂️ {t.pdf_lote}</button>
          <p className="en-hint">{mensaje ?? t.pdf_lote_ayuda(profesores.length)}</p>
        </>
      )}
    </div>
  );
}
