// Vista de alumnos (§7.4): filtros de cuestionario y grupo, indicadores, profesorado por
// asignatura, satisfacción por bloque y recomendación. Primera pantalla del paso 5.

import { useEffect, useMemo, useState, type ReactNode } from "react";
import { Migas } from "../componentes/Marco";
import { Oculto } from "../componentes/Oculto";
import {
  bloques as cargarBloques, cuestionarios as cargarCuestionarios, resultados,
  type Bloque, type Cuestionario, type Fila, type Filtro, type Resultado,
} from "../data/resultados";
import type { Perfil } from "../data/sesion";
import * as f from "../formato";
import { t } from "../i18n";

interface Datos {
  personas: Fila;
  grupos: Fila[];
  satisfaccion: Fila;
  profesorado: Fila;
  recomendacion: Fila;
  asignaturas: Fila[];
  bloques: { bloque: Bloque; fila: Fila }[];
}

const BLOQUES_APARTE = new Set(["profesorado", "satisfaccion_general", "recomendacion"]);

export function Alumnos({ perfil }: { perfil: Perfil }) {
  const [lista, setLista] = useState<Cuestionario[]>([]);
  const [cuestionario, setCuestionario] = useState<string>("");
  const [grupo, setGrupo] = useState<string>("");
  const [datos, setDatos] = useState<Datos | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    cargarCuestionarios("alumnos")
      .then((todos) => {
        // La coordinación solo ve los cuestionarios de su etapa (el servidor también lo impone).
        const l = perfil.rol === "coordinacion" ? todos.filter((c) => c.etapa === perfil.etapa) : todos;
        setLista(l);
        setCuestionario((c) => c || l[0]?.codigo || "");
        if (l.length === 0) setError(t.sin_cuestionarios);
      })
      .catch(() => setError(t.error_datos));
  }, [perfil]);

  useEffect(() => {
    if (!cuestionario) return;
    let vigente = true;
    setDatos(null);
    setError(null);
    const base: Filtro = { colectivo: "alumnos", cuestionario };
    const filtro: Filtro = grupo ? { ...base, grupo } : base;
    (async () => {
      const [personas, grupos, sat, prof, rec, asig, bl] = await Promise.all([
        resultados(filtro, { tipo: "personas" }),
        resultados(base, { tipo: "personas" }, ["grupo"]),
        resultados(filtro, { tipo: "bloque", codigo: "satisfaccion_general" }),
        resultados(filtro, { tipo: "bloque", codigo: "profesorado" }),
        resultados(filtro, { tipo: "recomendacion" }),
        resultados(filtro, { tipo: "bloque", codigo: "profesorado" }, ["asignatura"]),
        cargarBloques(cuestionario),
      ]);
      const deMedia = bl.filter((b) => b.entra_en_media && !BLOQUES_APARTE.has(b.codigo));
      const porBloque: Resultado[] = await Promise.all(
        deMedia.map((b) => resultados(filtro, { tipo: "bloque", codigo: b.codigo })));
      if (!vigente) return;
      setDatos({
        personas: personas.total,
        grupos: grupos.partes.filter((p) => p.clave.grupo !== "(sin dato)"),
        satisfaccion: sat.total,
        profesorado: prof.total,
        recomendacion: rec.total,
        asignaturas: asig.partes,
        bloques: deMedia.map((b, i) => ({ bloque: b, fila: porBloque[i].total })),
      });
    })().catch(() => vigente && setError(t.error_datos));
    return () => { vigente = false; };
  }, [cuestionario, grupo]);

  const actual = useMemo(() => lista.find((c) => c.codigo === cuestionario), [lista, cuestionario]);
  const escalaRec = actual?.etapa === "primaria" ? "1 a 10" : "0 a 10";

  return (
    <div className="page">
      <Migas actual={t.alu_titulo} />
      <p className="eyebrow">{t.alu_eyebrow}</p>
      <h1>🎒 {t.alu_titulo}</h1>
      <p className="lead">{t.alu_lead}</p>

      <div className="card en-filters en-noprint">
        <label>{t.cuestionario}
          <select value={cuestionario} onChange={(e) => { setCuestionario(e.target.value); setGrupo(""); }}>
            {lista.map((c) => <option key={c.codigo} value={c.codigo}>{c.titulo}</option>)}
          </select>
        </label>
        <label>{t.grupo}
          <select value={grupo} onChange={(e) => setGrupo(e.target.value)} disabled={!datos}>
            <option value="">{t.todos_grupos}</option>
            {datos?.grupos.map((g) => (
              <option key={g.clave.grupo} value={g.clave.grupo}>
                {g.clave.grupo}{g.suprimido ? ` (${g.motivo === "menos_de_5" ? t.oculto_menos5 : t.oculto_compl})` : ""}
              </option>
            ))}
          </select>
        </label>
      </div>

      {error && <p className="notice">{error}</p>}
      {!datos && !error && cuestionario && <p className="en-cargando">{t.cargando}</p>}
      {datos && (
        <>
          <h2 className="section-title">{t.indicadores}</h2>
          <p className="sec-lead">{t.indicadores_lead}</p>
          <div className="en-kpis">
            <Indicador destacado etiqueta={t.k_respuestas} fila={datos.personas}
              valor={(x) => f.recuento(x.n!)}
              detalle={() => !grupo && actual?.respuestas_incompletas ? t.k_incompletas(actual.respuestas_incompletas) : t.k_respuestas_d} />
            <Indicador etiqueta={t.k_satisfaccion} fila={datos.satisfaccion}
              valor={(x) => <>{f.media(x.media!)} <small>/ 6</small></>}
              detalle={(x) => t.k_satisfaccion_d(f.recuento(x.n_personas!))} />
            <Indicador etiqueta={t.k_profesorado} fila={datos.profesorado}
              valor={(x) => <>{f.media(x.media!)} <small>/ 6</small></>}
              detalle={() => t.k_profesorado_d} />
            <Indicador etiqueta={t.k_recomendacion} fila={datos.recomendacion}
              valor={(x) => <>{f.recomendacion(x.media!)} <small>/ 10</small></>}
              detalle={(x) => t.k_recomendacion_d(f.nps(x.nps!))} />
          </div>

          <div className="en-two" style={{ marginTop: "1.2rem" }}>
            <section className="card">
              <h3>{t.prof_asig}</h3>
              <p className="en-hint">{t.prof_asig_lead}</p>
              {datos.asignaturas.length === 0 ? <p className="en-hint">{t.sin_datos_seccion}</p>
                : ordenar(datos.asignaturas).map((a) => <Barra key={a.clave.asignatura} etiqueta={a.clave.asignatura} fila={a} />)}
            </section>
            <section className="card">
              <h3>{t.bloques}</h3>
              <p className="en-hint">{t.bloques_lead}</p>
              {datos.bloques.map(({ bloque, fila }) => <Barra key={bloque.codigo} etiqueta={bloque.nombre} fila={fila} />)}
            </section>
          </div>

          <h2 className="section-title">{t.recomendacion}</h2>
          <p className="sec-lead">{t.recomendacion_lead(escalaRec)}</p>
          <Recomendacion fila={datos.recomendacion} desde={actual?.etapa === "primaria" ? 1 : 0} />

          <p className="notice" style={{ marginTop: "1.4rem" }}>{t.leyenda_oculto} {t.aviso_cierre}</p>
        </>
      )}
    </div>
  );
}

function ordenar(filas: Fila[]): Fila[] {
  // Visibles de mayor a menor media; las ocultas al final, sin revelar orden por valor.
  return [...filas].sort((a, b) =>
    a.suprimido !== b.suprimido ? (a.suprimido ? 1 : -1)
      : a.suprimido ? 0 : (b.media ?? 0) - (a.media ?? 0));
}

function Indicador({ etiqueta, fila, valor, detalle, destacado }: {
  etiqueta: string; fila: Fila; valor: (x: Fila) => ReactNode; detalle: (x: Fila) => string; destacado?: boolean;
}) {
  return (
    <div className={`card en-kpi${destacado ? " hl" : ""}`}>
      <div className="l">{etiqueta}</div>
      <div className="v">{fila.suprimido ? <Oculto fila={fila} /> : valor(fila)}</div>
      <div className="d">{fila.suprimido ? "" : detalle(fila)}</div>
    </div>
  );
}

function Barra({ etiqueta, fila }: { etiqueta: string; fila: Fila }) {
  const ancho = fila.suprimido || fila.media == null ? 0 : ((fila.media - 1) / 5) * 100;
  return (
    <div className="en-bar">
      <span>{etiqueta}</span>
      <span className="en-track" aria-hidden="true"><span className="en-fill" style={{ width: `${ancho}%` }} /></span>
      <span className="en-val">
        {fila.suprimido ? <Oculto fila={fila} /> : <>{f.media(fila.media!)}<small>n {f.recuento(fila.n!)}</small></>}
      </span>
    </div>
  );
}

function Recomendacion({ fila, desde }: { fila: Fila; desde: number }) {
  if (fila.suprimido) return <div className="card"><Oculto fila={fila} /></div>;
  const tramos = [
    { clase: "en-n3", texto: t.detractores, pct: fila.detractores_pct ?? 0 },
    { clase: "en-neu", texto: t.neutros, pct: fila.neutros_pct ?? 0 },
    { clase: "en-p2", texto: t.promotores, pct: fila.promotores_pct ?? 0 },
  ];
  const dist = Object.entries(fila.distribucion ?? {})
    .map(([v, n]) => ({ v: Number(v), n }))
    .filter((d) => d.v >= desde)
    .sort((a, b) => a.v - b.v);
  const max = Math.max(1, ...dist.map((d) => d.n));
  const clase = (v: number) => (v <= 6 ? "en-n3" : v <= 8 ? "en-neu" : "en-p2");
  return (
    <div className="en-two">
      <section className="card">
        <h3>NPS {f.nps(fila.nps!)}</h3>
        <p className="en-hint">{t.media} {f.recomendacion(fila.media!)} · {f.recuento(fila.n!)} {t.respuestas}</p>
        <div className="en-apilada" role="img"
             aria-label={tramos.map((x) => `${x.texto} ${f.porcentaje(x.pct)}`).join(", ")}>
          {tramos.map((x) => <span key={x.clase} className={x.clase} style={{ width: `${x.pct}%` }} />)}
        </div>
        <div className="en-legend">
          {tramos.map((x) => <span key={x.clase}><i className={x.clase} />{x.texto} {f.porcentaje(x.pct)}</span>)}
        </div>
      </section>
      <section className="card">
        <div className="en-cols" aria-hidden="true">
          {dist.map((d) => (
            <div key={d.v} className="en-col">
              <span className="c">{d.n}</span>
              <span className={`b ${clase(d.v)}`} style={{ height: `${(d.n / max) * 100}%` }} />
            </div>
          ))}
        </div>
        <div className="en-colx">{dist.map((d) => <span key={d.v}>{d.v}</span>)}</div>
      </section>
    </div>
  );
}
