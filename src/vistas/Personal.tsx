// Vista de personal (§7.4 y §7.0): la encuesta de personal, con un enlace a «Informes por persona»
// (sección propia del menú). Un filtro a la vez (docentes o no docentes, o antigüedad),
// indicadores con la recomendación, dimensiones, Superiores agregado, reuniones de departamento por
// departamento, Equipo de Individuación, detalle por pregunta, recomendación y lo más
// valorado. Sin sexo.

import { useEffect, useState } from "react";
import {
  Barra, CabeceraPreguntas, FilaPregunta, Indicador, IndicadorRecomendacion, LeyendaAcuerdo, Ranking, Recomendacion,
} from "../componentes/Graficos";
import { Exportar } from "../componentes/Exportar";
import { Migas } from "../componentes/Marco";
import { aHash } from "../navegacion";
import {
  bloques as cargarBloques, cuestionarios as cargarCuestionarios, detallePreguntas, opciones, recuentoIdiomas, resultados,
  type Bloque, type Cuestionario, type DetallePregunta, type Fila, type Filtro,
} from "../data/resultados";
import {
  celdas, notasComunes, tablaDetalle, tablaDistribucion, tablaMedias, tablaRecomendacion, tablaValorado, txt, type Exportacion,
} from "../exportacion/modelo";
import * as f from "../formato";
import { t } from "../i18n";
import { SinResultados, useHayResultados } from "../componentes/SinResultados";

type Segmento =
  | null
  | { docente: true } | { docente: false }
  | { antiguedad: "primer_ano" } | { antiguedad: "mas_de_un_ano" };

const SEGMENTOS: { clave: string; seg: Segmento; texto: string }[] = [
  { clave: "todos", seg: null, texto: t.per_todos },
  { clave: "docentes", seg: { docente: true }, texto: t.per_docentes },
  { clave: "no_docentes", seg: { docente: false }, texto: t.per_no_docentes },
  { clave: "primer_ano", seg: { antiguedad: "primer_ano" }, texto: t.per_primer_ano },
  { clave: "mas_de_un_ano", seg: { antiguedad: "mas_de_un_ano" }, texto: t.per_mas_de_un_ano },
];

const DETALLE = ["centro", "condiciones", "relaciones", "superiores", "puesto", "satisfaccion",
                 "equipo_individualizacion", "perfil_ib", "pep", "pai"];

interface Datos {
  personas: Fila;
  satisfaccion: Fila;
  recomendacion: Fila;
  superiores: Fila;
  superioresPorTipo: Fila[];
  equipo: Fila;
  dimensiones: { bloque: Bloque; fila: Fila }[];
  departamentos: Fila[] | null;
  idiomas: Record<string, number> | null;
  valorado: Fila;
}

/** Personal (§7.0): la encuesta de personal. La coordinación no entra (§6). */
export function Personal() {
  const hayPersonal = useHayResultados("personal");
  return (
    <div className="page">
      <Migas actual={t.per_titulo} />
      <p className="eyebrow">{t.alu_eyebrow}</p>
      <h1>🧑‍🏫 {t.per_titulo}</h1>
      <p className="lead">{t.per_lead_general}</p>
      <p className="en-enlace-informes en-noprint">
        {t.per_enlace_informes} <a href={aHash({ seccion: "/informes", nivel: "direccion" })}>{t.nav_informes} →</a>
      </p>
      {hayPersonal ? <EncuestaPersonal /> : <SinResultados colectivo="personal" />}
    </div>
  );
}

function EncuestaPersonal() {
  const [clave, setClave] = useState("todos");
  const segmento = SEGMENTOS.find((s) => s.clave === clave)!.seg;
  const filtro: Filtro = { colectivo: "personal", ...(segmento ?? {}) };
  const [cuest, setCuest] = useState<Cuestionario | null>(null);
  const [bl, setBl] = useState<Bloque[]>([]);
  const [textos, setTextos] = useState<Record<string, string>>({});
  const [datos, setDatos] = useState<Datos | null>(null);
  const [bloqueDetalle, setBloqueDetalle] = useState("superiores");
  const [detalle, setDetalle] = useState<DetallePregunta[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    cargarCuestionarios("personal").then((l) => setCuest(l[0] ?? null)).catch(() => {});
    cargarBloques("PER").then(setBl).catch(() => {});
    opciones("mas_valorado").then(setTextos).catch(() => {});
  }, []);

  useEffect(() => {
    if (!cuest || bl.length === 0) return;
    let vigente = true;
    setDatos(null);
    setError(null);
    const sinFiltro = segmento === null;
    (async () => {
      const dims = bl.filter((b) => b.entra_en_media);
      const idiomas = cuest.idiomas_cargados.includes("en") ? await recuentoIdiomas() : null;
      const [personas, sat, rec, sup, supTipo, equipo, valorado, deps, ...porBloque] = await Promise.all([
        resultados(filtro, { tipo: "personas" }),
        resultados(filtro, { tipo: "satisfaccion" }),
        resultados(filtro, { tipo: "recomendacion" }),
        resultados(filtro, { tipo: "bloque", codigo: "superiores" }),
        sinFiltro ? resultados(filtro, { tipo: "bloque", codigo: "superiores" }, ["docente"]) : null,
        resultados(filtro, { tipo: "bloque", codigo: "equipo_individualizacion" }),
        resultados(filtro, { tipo: "seleccion", codigo: "mas_valorado" }),
        // Las reuniones de departamento solo se consultan por departamento y sin otros filtros (§5.7).
        sinFiltro ? resultados({ colectivo: "personal" }, { tipo: "bloque", codigo: "reuniones_departamento" }, ["departamento"]) : null,
        ...dims.map((b) => resultados(filtro, { tipo: "bloque", codigo: b.codigo })),
      ]);
      if (!vigente) return;
      setDatos({
        personas: personas!.total, satisfaccion: sat!.total, recomendacion: rec!.total,
        superiores: sup!.total,
        superioresPorTipo: ["docente", "no_docente"].map((k) => supTipo?.partes.find((p) => p.clave.docente === k)).filter((p): p is Fila => !!p),
        equipo: equipo!.total, valorado: valorado!.total,
        departamentos: deps ? deps.partes : null,
        idiomas,
        dimensiones: dims.map((b, i) => ({ bloque: b, fila: porBloque[i]!.total })),
      });
    })().catch(() => vigente && setError(t.error_datos));
    return () => { vigente = false; };
  }, [clave, cuest, bl]);

  useEffect(() => {
    let vigente = true;
    setDetalle(null);
    detallePreguntas(filtro, bloqueDetalle).then((d) => vigente && setDetalle(d)).catch(() => vigente && setDetalle([]));
    return () => { vigente = false; };
  }, [clave, bloqueDetalle]);

  const escalaBloque = (b: string) => (b === "perfil_ib" ? t.escala_frecuencia : t.escala_acuerdo_per);
  const etiquetas = escalaBloque(bloqueDetalle);
  const nombreBloque = (c: string) => bl.find((b) => b.codigo === c)?.nombre ?? c;

  /** Lo que se ve en pantalla, con el detalle de todos los bloques, para el CSV y el PDF. */
  async function preparar(): Promise<Exportacion> {
    const d = datos!;
    const codigos = DETALLE.filter((c) => bl.some((b) => b.codigo === c));
    const detalles = await Promise.all(codigos.map((c) => detallePreguntas(filtro, c)));
    const texto = SEGMENTOS.find((x) => x.clave === clave)!.texto;
    const superiores = d.superioresPorTipo.length > 1
      ? d.superioresPorTipo.map((x) => ({ etiqueta: x.clave.docente === "docente" ? t.per_docentes : t.per_no_docentes, fila: x }))
      : [{ etiqueta: d.superiores.suprimido ? texto : t.per_no_docentes, fila: d.superiores }];
    return {
      vista: "personal", titulo: t.per_titulo,
      filtros: segmento ? [[t.exp_personas_filtro, texto]] : [],
      archivo: [t.per_titulo, ...(segmento ? [texto] : [])],
      tablas: [
        {
          titulo: t.indicadores, columnas: [t.exp_col_indicador, t.exp_col_valor, t.exp_col_personas],
          filas: [
            [txt(t.k_respuestas), ...celdas(d.personas, ["n", "n"])],
            [txt(`${t.k_satisfaccion_media} (de 1 a 6)`), ...celdas(d.satisfaccion, ["media", "personas"])],
            [txt(`${t.k_superiores} (de 1 a 6)`), ...celdas(d.superiores, ["media", "personas"])],
          ],
          notas: [t.tip_k_personal, ...(segmento === null && cuest ? [notaIdioma(cuest, d.idiomas)] : [])],
        },
        tablaRecomendacion(t.per_recomendacion, t.per_titulo, "1 a 10", d.recomendacion),
        tablaDistribucion(d.recomendacion, 1),
        tablaMedias(t.per_dimensiones, t.exp_col_bloque, d.dimensiones.map(({ bloque, fila }) => ({ etiqueta: bloque.nombre, fila }))),
        tablaMedias(t.per_superiores, t.exp_col_quien, superiores, [t.per_superiores_quien, t.per_superiores_nota]),
        d.departamentos === null
          ? { titulo: t.per_departamentos, columnas: [], filas: [], notas: [t.per_departamentos_sin_filtro] }
          : tablaMedias(t.per_departamentos, t.exp_col_departamento,
              [...d.departamentos].sort((a, b) => a.clave.departamento.localeCompare(b.clave.departamento, "es"))
                .map((x) => ({ etiqueta: x.clave.departamento, fila: x })), [t.per_departamentos_lead]),
        tablaMedias(nombreBloque("equipo_individualizacion"), t.exp_col_bloque, [{ etiqueta: t.per_equipo_barra, fila: d.equipo }], [t.per_equipo_lead]),
        ...codigos.map((c, i) => tablaDetalle(nombreBloque(c),
          detalles[i].map((x) => ({ texto: x.texto, fila: x.resultado.total })), escalaBloque(c))),
        tablaValorado(t.valorado, d.valorado, textos),
      ],
      notas: [t.per_aviso, ...notasComunes()],
    };
  }

  return (
    <section>
      <h2 className="section-title">{t.per_sub_encuesta}</h2>
      <p className="sec-lead">{t.per_lead}</p>

      <div className="chips en-noprint" role="group" aria-label={t.per_filtro}>
        {SEGMENTOS.map((s) => (
          <button key={s.clave} className={`chip${clave === s.clave ? " on" : ""}`} aria-pressed={clave === s.clave}
                  onClick={() => setClave(s.clave)}>
            {s.texto}
          </button>
        ))}
      </div>
      <p className="en-hint">{t.per_filtro_nota}</p>
      <Exportar preparar={preparar} disabled={!datos} />


      {error && <p className="notice en-alerta en-alerta-neg" role="alert">{error}</p>}
      {!datos && !error && <p className="en-cargando">{t.cargando}</p>}
      {datos && cuest && (
        <>
          {datos.personas.suprimido && <p className="notice en-alerta">{t.per_segmento_oculto}</p>}

          <h2 className="section-title">{t.indicadores}</h2>
          <p className="sec-lead">{t.per_indicadores_lead}</p>
          <div className="en-kpis">
            <Indicador destacado etiqueta={t.k_respuestas} fila={datos.personas} explicacion={t.tip_k_personal}
              valor={(x) => f.recuento(x.n!)}
              detalle={() => [
                segmento === null && cuest.respuestas_incompletas ? t.k_incompletas(cuest.respuestas_incompletas) : null,
                segmento === null ? notaIdioma(cuest, datos.idiomas) : null,
              ].filter(Boolean).join(" · ") || t.k_personal_d} />
            <Indicador etiqueta={t.k_satisfaccion_media} fila={datos.satisfaccion} explicacion={t.tip_k_satisfaccion_per}
              valor={(x) => <>{f.media(x.media!)} <small>/ 6</small></>}
              detalle={() => t.k_dimensiones_d} />
            <Indicador etiqueta={t.k_superiores} fila={datos.superiores} explicacion={`${t.tip_k_superiores} ${t.per_superiores_quien}`}
              valor={(x) => <>{f.media(x.media!)} <small>/ 6</small></>}
              detalle={(x) => t.tip_personas(f.recuento(x.n!))} />
            <IndicadorRecomendacion etiqueta={t.k_recomendacion_trabajo} fila={datos.recomendacion} />
          </div>

          <div className="en-two" style={{ marginTop: "1.2rem" }}>
            <section className="card">
              <h3>{t.per_dimensiones}</h3>
              <p className="en-hint">{t.per_dimensiones_lead}</p>
              {datos.dimensiones.map(({ bloque, fila }) => <Barra key={bloque.codigo} etiqueta={bloque.nombre} fila={fila} />)}
            </section>
            <section className="card">
              <h3>{t.per_superiores}</h3>
              <p className="en-hint">{t.per_superiores_lead}</p>
              {datos.superioresPorTipo.length > 1
                ? datos.superioresPorTipo.map((p) => (
                    <Barra key={p.clave.docente} etiqueta={p.clave.docente === "docente" ? t.per_docentes : t.per_no_docentes} fila={p} />))
                : <Barra etiqueta={datos.superiores.suprimido ? SEGMENTOS.find((s) => s.clave === clave)!.texto : t.per_no_docentes} fila={datos.superiores} />}
              <p className="en-hint" style={{ marginTop: ".6rem" }}>{t.per_superiores_quien}</p>
              <p className="notice en-alerta" style={{ marginTop: ".8rem" }}>{t.per_superiores_nota}</p>
            </section>
          </div>

          <div className="en-two" style={{ marginTop: ".9rem" }}>
            <section className="card">
              <h3>{t.per_departamentos}</h3>
              <p className="en-hint">{t.per_departamentos_lead}</p>
              {datos.departamentos === null ? <p className="en-hint">{t.per_departamentos_sin_filtro}</p>
                : [...datos.departamentos].sort((a, b) => a.clave.departamento.localeCompare(b.clave.departamento, "es"))
                    .map((p) => <Barra key={p.clave.departamento} etiqueta={p.clave.departamento} fila={p} />)}
            </section>
            <section className="card">
              <h3>{nombreBloque("equipo_individualizacion")}</h3>
              <p className="en-hint">{t.per_equipo_lead}</p>
              <Barra etiqueta={t.per_equipo_barra} fila={datos.equipo} />
            </section>
          </div>

          <h2 className="section-title">{t.detalle}</h2>
          <p className="sec-lead">{t.detalle_lead}</p>
          <div className="card">
            <div className="en-toolbar en-noprint">
              <label className="en-filters" style={{ display: "grid" }}>
                <span>{t.bloque}</span>
                <span className="en-select">
                  <select value={bloqueDetalle} onChange={(e) => setBloqueDetalle(e.target.value)}>
                    {DETALLE.filter((c) => bl.some((b) => b.codigo === c)).map((c) => <option key={c} value={c}>{nombreBloque(c)}</option>)}
                  </select>
                </span>
              </label>
            </div>
            <LeyendaAcuerdo etiquetas={etiquetas} />
            <CabeceraPreguntas />
            {!detalle ? <p className="en-cargando">{t.cargando}</p>
              : detalle.map((d) => <FilaPregunta key={d.codigo} texto={d.texto} fila={d.resultado.total} etiquetas={etiquetas} />)}
          </div>

          <h2 className="section-title">{t.per_recomendacion}</h2>
          <p className="sec-lead">{t.recomendacion_lead("1 a 10")}</p>
          <Recomendacion fila={datos.recomendacion} desde={1} />

          <h2 className="section-title">{t.valorado}</h2>
          <p className="sec-lead">{t.per_valorado_lead}</p>
          <div className="card"><Ranking fila={datos.valorado} textos={textos} /></div>

          <p className="notice en-alerta" style={{ marginTop: "1.4rem" }}>{t.per_aviso} {t.leyenda_oculto}</p>
        </>
      )}
    </section>
  );
}

/** Dato de idioma junto a las respuestas: cifras exactas. Es informativo y queda fuera de la
 *  supresión porque no existe ningún resultado por idioma (§5). */
function notaIdioma(c: Cuestionario, idiomas: Record<string, number> | null): string {
  if (!c.idiomas_cargados.includes("en") || !idiomas) return t.per_ingles_pendiente;
  return `${f.recuento(idiomas.es ?? 0)} ${t.en_espanol} · ${f.recuento(idiomas.en ?? 0)} ${t.en_ingles}`;
}
