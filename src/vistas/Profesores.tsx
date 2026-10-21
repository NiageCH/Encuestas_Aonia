// Informe por profesor (§7.2 y §7.0), dentro de Personal → Informes por persona: lo que opinan
// los alumnos de cada docente. Buscador, «Sus clases» (único docente o alumnos que escribieron su
// nombre; de ahí sale la media global) y «Valoraciones compartidas» (varios docentes), con el
// mínimo de 5 y la complementaria, comparación con su etapa y el colegio, y detalle por pregunta.

import { useEffect, useMemo, useRef, useState } from "react";
import { useAyuda } from "../componentes/Ayuda";
import { Barra } from "../componentes/Graficos";
import type { Perfil } from "../data/sesion";
import { Oculto } from "../componentes/Oculto";
import {
  listarProfesores, preguntasProfesorado, resultadosProfesor,
  type PreguntaBloque, type Profesor, type ResultadoProfesor,
} from "../data/resultados";
import { etiquetaClase, ordenarClases } from "../etiquetas";
import * as f from "../formato";
import { t } from "../i18n";

export function InformesProfesor({ perfil }: { perfil: Perfil }) {
  const [lista, setLista] = useState<Profesor[] | null>(null);
  const [busqueda, setBusqueda] = useState("");
  const [elegido, setElegido] = useState<Profesor | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => { listarProfesores().then(setLista).catch(() => setError(t.error_datos)); }, []);

  const filtrados = useMemo(() => {
    const q = normal(busqueda);
    return (lista ?? []).filter((p) => !q || normal(`${p.nombre} ${p.apellidos} ${p.departamento ?? ""}`).includes(q));
  }, [lista, busqueda]);

  return (
    <section>
      <h2 className="section-title">{t.prof_titulo}</h2>
      <p className="sec-lead">{perfil.rol === "coordinacion" ? t.prof_lead_coord : t.prof_lead}</p>
      {error && <p className="notice">{error}</p>}
      {lista && lista.length === 0 && <p className="notice">{t.prof_sin_profesores}</p>}
      {lista && lista.length > 0 && (
        <div className="en-prof">
          <div className="card en-prof-buscador en-noprint">
            <label className="en-filters" style={{ display: "grid" }}>
              <span>{t.prof_buscar}</span>
              <input type="search" className="en-input" value={busqueda} onChange={(e) => setBusqueda(e.target.value)}
                     placeholder={t.prof_buscar_ph} autoComplete="off" />
            </label>
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
            <Lote profesores={lista} />
          </div>
          <div>{elegido ? <Informe profesor={elegido} /> : <p className="en-hint">{t.prof_elige}</p>}</div>
        </div>
      )}
    </section>
  );
}

function normal(s: string) {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
}

function Informe({ profesor }: { profesor: Profesor }) {
  const ayuda = useAyuda();
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

  if (error) return <p className="notice">{error}</p>;
  if (!datos) return <p className="en-cargando">{t.cargando}</p>;

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
        <BotonPdf profesor={profesor} />
        <div className="en-kpis en-kpis3">
          <div className="card en-kpi hl en-con-ayuda" {...ayuda([t.prof_media_global, t.prof_media_global_tip])}>
            <div className="l">{t.prof_media_global}</div>
            <div className="v">{g.suprimido ? <span className="en-oculto">{t.prof_sin_visibles}</span> : <>{f.media(g.media!)} <small>/ 6</small></>}</div>
            <div className="d">{g.suprimido ? "" : t.prof_global_d(g.combinaciones!, f.recuento(g.n_valoraciones!))}</div>
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
        {datos.combinaciones_excluidas > 0 && <p className="notice" style={{ marginTop: ".9rem" }}>{t.prof_excluidas(datos.combinaciones_excluidas)}</p>}
      </div>

      <div className="card" style={{ marginTop: ".9rem" }}>
        <h3>{t.prof_por_asignatura}</h3>
        <p className="en-hint">{t.prof_por_asignatura_lead}</p>
        {propias.length === 0 ? <p className="en-hint">{compartidas.length ? t.prof_sin_propias : t.sin_datos_seccion}</p>
          : propias.map((c) => <Barra key={`${c.clave.cuestionario}-${c.clave.grupo}-${c.clave.asignatura}`} etiqueta={etiquetaClase(c)} fila={c} />)}
      </div>

      {compartidas.length > 0 && (
        <div className="card" style={{ marginTop: ".9rem" }}>
          <h3>{t.prof_compartidas}</h3>
          <p className="notice">{t.prof_compartidas_nota}</p>
          {compartidas.map((c) => <Barra key={`${c.clave.cuestionario}-${c.clave.grupo}-${c.clave.asignatura}`} etiqueta={etiquetaClase(c)} fila={c} />)}
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
                    <td className="n en-con-ayuda" {...ayuda(r.global.suprimido ? [p.texto, t.prof_sin_visibles]
                      : [p.texto, t.tip_media(f.media(r.global.media!)), t.tip_valoraciones(f.recuento(r.global.n_valoraciones!))])}>
                      {r.global.suprimido ? <span className="en-oculto">{t.oculto_menos5}</span> : <strong>{f.media(r.global.media!)}</strong>}
                    </td>
                    {etapas.map((e) => <td key={e} className="n">{celda(r.comparacion[e])}</td>)}
                    {datos.comparacion.colegio && <td className="n">{celda(r.comparacion.colegio)}</td>}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
      <p className="notice" style={{ marginTop: ".9rem" }}>{t.leyenda_oculto}</p>
    </div>
  );

  function celda(fila?: ResultadoProfesor["comparacion"][string]) {
    if (!fila) return "";
    return fila.suprimido ? <Oculto fila={fila} /> : f.media(fila.media!);
  }
}

function BotonPdf({ profesor }: { profesor: Profesor }) {
  const [estado, setEstado] = useState<"" | "generando" | "error">("");
  async function generar() {
    setEstado("generando");
    try {
      const { descargarInforme } = await import("../pdf/generar");
      await descargarInforme(profesor);
      setEstado("");
    } catch {
      setEstado("error");
    }
  }
  return (
    <p className="en-noprint">
      <button type="button" className="btn primary" onClick={generar} disabled={estado === "generando"}>
        📄 {estado === "generando" ? t.pdf_generando : t.pdf_descargar}
      </button>
      {estado === "error" && <span className="en-error" role="alert"> {t.pdf_error}</span>}
    </p>
  );
}

function Lote({ profesores }: { profesores: Profesor[] }) {
  const [progreso, setProgreso] = useState<[number, number] | null>(null);
  const [mensaje, setMensaje] = useState<string | null>(null);
  const cancelar = useRef(false);
  async function generar() {
    cancelar.current = false;
    setMensaje(null);
    setProgreso([0, profesores.length]);
    try {
      const { descargarLote } = await import("../pdf/generar");
      const hechos = await descargarLote(profesores, (n, total) => setProgreso([n, total]), () => cancelar.current);
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
          <p className="en-hint" role="status">{t.pdf_lote_progreso(progreso[0], progreso[1])}</p>
          <progress max={progreso[1]} value={progreso[0]} />
          <button type="button" className="btn" onClick={() => { cancelar.current = true; }}>{t.pdf_lote_cancelar}</button>
        </>
      ) : (
        <>
          <button type="button" className="btn" onClick={generar}>🗂️ {t.pdf_lote}</button>
          <p className="en-hint">{mensaje ?? t.pdf_lote_ayuda(profesores.length)}</p>
        </>
      )}
    </div>
  );
}
