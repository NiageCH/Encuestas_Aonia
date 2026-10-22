// Vista de alumnos (§7.4): filtros de cuestionario y grupo, indicadores, profesorado por
// asignatura, satisfacción por bloque y recomendación. Primera pantalla del paso 5.

import { useEffect, useMemo, useState } from "react";
import { Barra, Indicador, IndicadorRecomendacion, ordenar, Recomendacion } from "../componentes/Graficos";
import { Exportar } from "../componentes/Exportar";
import { Migas } from "../componentes/Marco";
import {
  bloques as cargarBloques, cuestionarios as cargarCuestionarios, resultados,
  type Bloque, type Cuestionario, type Fila, type Filtro, type Resultado,
} from "../data/resultados";
import type { Perfil } from "../data/sesion";
import {
  celdas, notasComunes, tablaDistribucion, tablaMedias, tablaRecomendacion, txt, type Exportacion,
} from "../exportacion/modelo";
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

  /** Lo que se ve en pantalla, para el CSV y el PDF. */
  async function preparar(): Promise<Exportacion> {
    const d = datos!;
    const titulo = actual?.titulo ?? cuestionario;
    return {
      vista: "alumnos", titulo: t.alu_titulo,
      filtros: [[t.exp_cuestionario, titulo], ...(grupo ? [[t.exp_grupo, grupo] as [string, string]] : [])],
      archivo: [t.alu_titulo, titulo, ...(grupo ? [`${t.exp_grupo}-${grupo}`] : [])],
      tablas: [
        {
          titulo: t.indicadores, columnas: [t.exp_col_indicador, t.exp_col_valor, t.exp_col_personas],
          filas: [
            [txt(t.k_respuestas), ...celdas(d.personas, ["n", "n"])],
            [txt(`${t.k_satisfaccion} (de 1 a 6)`), ...celdas(d.satisfaccion, ["media", "personas"])],
            [txt(`${t.k_profesorado} (de 1 a 6)`), ...celdas(d.profesorado, ["media", "personas"])],
          ],
          notas: [t.tip_k_satisfaccion, t.tip_k_profesorado],
        },
        tablaRecomendacion(t.recomendacion, t.alu_titulo, escalaRec, d.recomendacion),
        tablaDistribucion(d.recomendacion, actual?.etapa === "primaria" ? 1 : 0),
        tablaMedias(t.prof_asig, t.exp_col_asignatura, ordenar(d.asignaturas).map((a) => ({ etiqueta: a.clave.asignatura, fila: a })), [t.prof_asig_lead]),
        tablaMedias(t.bloques, t.exp_col_bloque, d.bloques.map(({ bloque, fila }) => ({ etiqueta: bloque.nombre, fila }))),
        ...(grupo ? [] : [{
          titulo: t.exp_respuestas_grupo, columnas: [t.exp_col_grupo, t.exp_col_personas],
          filas: d.grupos.map((g) => [txt(g.clave.grupo), ...celdas(g, ["n"])]),
        }]),
      ],
      notas: notasComunes(),
    };
  }

  return (
    <div className="page">
      <Migas actual={t.alu_titulo} />
      <p className="eyebrow">{t.alu_eyebrow}</p>
      <h1>🎒 {t.alu_titulo}</h1>
      <p className="lead">{t.alu_lead}</p>

      <div className="card en-filters en-noprint">
        <label><span>{t.cuestionario}</span>
          <span className="en-select">
            <select value={cuestionario} onChange={(e) => { setCuestionario(e.target.value); setGrupo(""); }}>
              {lista.map((c) => <option key={c.codigo} value={c.codigo}>{c.titulo}</option>)}
            </select>
          </span>
        </label>
        <label><span>{t.grupo}</span>
          <span className="en-select">
          <select value={grupo} onChange={(e) => setGrupo(e.target.value)} disabled={!datos}>
            <option value="">{t.todos_grupos}</option>
            {datos?.grupos.map((g) => (
              <option key={g.clave.grupo} value={g.clave.grupo}>
                {g.clave.grupo}{g.suprimido ? ` (${g.motivo === "menos_de_5" ? t.oculto_menos5 : t.oculto_compl})` : ""}
              </option>
            ))}
          </select>
          </span>
        </label>
      </div>

      <Exportar preparar={preparar} disabled={!datos} />

      {error && <p className="notice">{error}</p>}
      {!datos && !error && cuestionario && <p className="en-cargando">{t.cargando}</p>}
      {datos && (
        <>
          <h2 className="section-title">{t.indicadores}</h2>
          <p className="sec-lead">{t.indicadores_lead}</p>
          <div className="en-kpis">
            <Indicador destacado etiqueta={t.k_respuestas} fila={datos.personas} explicacion={t.tip_k_respuestas}
              valor={(x) => f.recuento(x.n!)}
              detalle={() => !grupo && actual?.respuestas_incompletas ? t.k_incompletas(actual.respuestas_incompletas) : t.k_respuestas_d} />
            <Indicador etiqueta={t.k_satisfaccion} fila={datos.satisfaccion} explicacion={t.tip_k_satisfaccion}
              valor={(x) => <>{f.media(x.media!)} <small>/ 6</small></>}
              detalle={(x) => t.k_satisfaccion_d(f.recuento(x.n_personas!))} />
            <Indicador etiqueta={t.k_profesorado} fila={datos.profesorado} explicacion={t.tip_k_profesorado}
              valor={(x) => <>{f.media(x.media!)} <small>/ 6</small></>}
              detalle={() => t.k_profesorado_d} />
            <IndicadorRecomendacion etiqueta={t.k_recomendacion} fila={datos.recomendacion} />
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

