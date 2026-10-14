// Informes por profesor (§7.2), dentro de Personal → Docentes (§7.0): buscador, resultados
// por asignatura y grupo (las combinaciones con menos de 5 respuestas se ocultan), media
// global con las combinaciones visibles, comparación con su etapa y el colegio, y detalle
// por pregunta.

import { useEffect, useMemo, useState } from "react";
import { useAyuda } from "../componentes/Ayuda";
import { Barra } from "../componentes/Graficos";
import { Oculto } from "../componentes/Oculto";
import {
  listarProfesores, preguntasProfesorado, resultadosProfesor,
  type PreguntaBloque, type Profesor, type ResultadoProfesor,
} from "../data/resultados";
import * as f from "../formato";
import { t } from "../i18n";

export function Profesores() {
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
      <p className="sec-lead">{t.prof_lead}</p>
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
                    <strong>{p.apellidos}, {p.nombre}</strong>
                    {p.departamento && <small>{p.departamento}</small>}
                  </button>
                </li>
              ))}
            </ul>
            {filtrados.length > 60 && <p className="en-hint">{t.prof_mas(filtrados.length - 60)}</p>}
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
  const celdas = [...datos.celdas].sort((a, b) =>
    a.clave.asignatura.localeCompare(b.clave.asignatura, "es") || a.clave.grupo.localeCompare(b.clave.grupo, "es", { numeric: true }));

  return (
    <div className="en-informe">
      <div className="card">
        <p className="eyebrow">{t.prof_informe}</p>
        <h3 className="en-prof-nombre">{profesor.nombre} {profesor.apellidos}</h3>
        {profesor.departamento && <p className="en-hint">{t.prof_departamento}: {profesor.departamento}</p>}
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
        {celdas.length === 0 ? <p className="en-hint">{t.sin_datos_seccion}</p>
          : celdas.map((c) => (
              <Barra key={`${c.clave.cuestionario}-${c.clave.grupo}-${c.clave.asignatura}`}
                     etiqueta={`${c.clave.asignatura} · ${c.clave.grupo}`} fila={c} />
            ))}
      </div>

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
