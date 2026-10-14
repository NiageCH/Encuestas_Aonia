// Vista de familias (§7.4): filtro por etapa, valoración general del centro destacada y por
// etapa, bloques, detalle por pregunta, recomendación y NPS, y lo más valorado.
// Una familia con hijos en varias etapas cuenta en cada una (§5.6).

import { useEffect, useState } from "react";
import {
  Barra, CabeceraPreguntas, FilaPregunta, Indicador, LeyendaAcuerdo, Ranking, Recomendacion,
} from "../componentes/Graficos";
import { Migas } from "../componentes/Marco";
import {
  bloques as cargarBloques, cuestionarios as cargarCuestionarios, detallePreguntas, opciones, resultados,
  type Bloque, type DetallePregunta, type Fila, type Filtro,
} from "../data/resultados";
import type { Perfil } from "../data/sesion";
import * as f from "../formato";
import { t } from "../i18n";

const ETAPAS = ["infantil", "primaria", "pai", "bachillerato"] as const;
type Etapa = (typeof ETAPAS)[number];

interface Datos {
  personas: Fila;
  general: Fila;
  satisfaccion: Fila;
  recomendacion: Fila;
  porEtapa: Fila[];
  sinEtapa: Fila | null;
  bloques: { bloque: Bloque; fila: Fila }[];
  valorado: Fila;
}

export function Familias({ perfil }: { perfil: Perfil }) {
  const fija = perfil.rol === "coordinacion" ? (perfil.etapa as Etapa) : null;
  const [etapa, setEtapa] = useState<Etapa | "">(fija ?? "");
  const [datos, setDatos] = useState<Datos | null>(null);
  const [incompletas, setIncompletas] = useState(0);
  const [textos, setTextos] = useState<Record<string, string>>({});
  const [bloqueDetalle, setBloqueDetalle] = useState("general");
  const [detalle, setDetalle] = useState<DetallePregunta[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const filtro: Filtro = etapa ? { colectivo: "familias", etapa } : { colectivo: "familias" };

  useEffect(() => {
    cargarCuestionarios("familias").then((l) => setIncompletas(l[0]?.respuestas_incompletas ?? 0)).catch(() => {});
    opciones("mas_valorado").then(setTextos).catch(() => {});
  }, []);

  useEffect(() => {
    let vigente = true;
    setDatos(null);
    setError(null);
    (async () => {
      const [personas, general, sat, rec, valorado, bl] = await Promise.all([
        resultados(filtro, { tipo: "personas" }),
        resultados(filtro, { tipo: "bloque", codigo: "general" }),
        resultados(filtro, { tipo: "satisfaccion" }),
        resultados(filtro, { tipo: "recomendacion" }),
        resultados(filtro, { tipo: "seleccion", codigo: "mas_valorado" }),
        cargarBloques("FAM"),
      ]);
      // Comparación por etapa: solo para quien ve todas las etapas.
      const porEtapa = fija ? null : await resultados({ colectivo: "familias" }, { tipo: "bloque", codigo: "general" }, ["etapa"]);
      // Familias sin ninguna etapa marcada: parte implícita «Sin etapa» (§5.6).
      const personasEtapa = fija ? null : await resultados({ colectivo: "familias" }, { tipo: "personas" }, ["etapa"]);
      const deMedia = bl.filter((b) => b.entra_en_media);
      const porBloque = await Promise.all(deMedia.map((b) => resultados(filtro, { tipo: "bloque", codigo: b.codigo })));
      if (!vigente) return;
      setDatos({
        personas: personas.total, general: general.total, satisfaccion: sat.total, recomendacion: rec.total,
        valorado: valorado.total,
        porEtapa: ETAPAS.map((e) => porEtapa?.partes.find((p) => p.clave.etapa === e)).filter((p): p is Fila => !!p),
        sinEtapa: personasEtapa?.partes.find((p) => p.clave.etapa === "(sin dato)") ?? null,
        bloques: deMedia.map((b, i) => ({ bloque: b, fila: porBloque[i].total })),
      });
    })().catch(() => vigente && setError(t.error_datos));
    return () => { vigente = false; };
  }, [etapa]);

  useEffect(() => {
    let vigente = true;
    setDetalle(null);
    detallePreguntas(filtro, bloqueDetalle).then((d) => vigente && setDetalle(d)).catch(() => vigente && setDetalle([]));
    return () => { vigente = false; };
  }, [etapa, bloqueDetalle]);

  const etiquetas = bloqueDetalle === "servicios" ? t.escala_satisfaccion_fam : t.escala_acuerdo_fam;

  return (
    <div className="page">
      <Migas actual={t.fam_titulo} />
      <p className="eyebrow">{t.alu_eyebrow}</p>
      <h1>👪 {t.fam_titulo}</h1>
      <p className="lead">{t.fam_lead}</p>

      <div className="chips en-noprint" role="group" aria-label={t.etapa}>
        {!fija && (
          <button className={`chip${etapa === "" ? " on" : ""}`} aria-pressed={etapa === ""} onClick={() => setEtapa("")}>
            {t.todas_etapas}
          </button>
        )}
        {ETAPAS.filter((e) => !fija || e === fija).map((e) => (
          <button key={e} className={`chip${etapa === e ? " on" : ""}`} aria-pressed={etapa === e} onClick={() => setEtapa(e)}>
            {t.etapas[e]}
          </button>
        ))}
      </div>

      {error && <p className="notice">{error}</p>}
      {!datos && !error && <p className="en-cargando">{t.cargando}</p>}
      {datos && (
        <>
          {datos.personas.suprimido && <p className="notice">{t.fam_etapa_oculta}</p>}

          <h2 className="section-title">{t.indicadores}</h2>
          <p className="sec-lead">{t.fam_indicadores_lead}</p>
          <div className="en-kpis">
            <Indicador destacado etiqueta={t.k_respuestas} fila={datos.personas} explicacion={t.tip_k_familias}
              valor={(x) => f.recuento(x.n!)}
              detalle={() => [!etapa && incompletas ? t.k_incompletas(incompletas) : t.k_familias_d,
                              !etapa && datos.sinEtapa ? notaSinEtapa(datos.sinEtapa) : null].filter(Boolean).join(" · ")} />
            <Indicador etiqueta={t.k_general} fila={datos.general} explicacion={t.tip_k_general}
              valor={(x) => <>{f.media(x.media!)} <small>/ 6</small></>}
              detalle={(x) => t.tip_personas(f.recuento(x.n!))} />
            <Indicador etiqueta={t.k_satisfaccion_media} fila={datos.satisfaccion} explicacion={t.tip_k_satisfaccion_media}
              valor={(x) => <>{f.media(x.media!)} <small>/ 6</small></>}
              detalle={() => t.k_satisfaccion_media_d} />
            <Indicador etiqueta={t.k_recomendacion} fila={datos.recomendacion} explicacion={t.tip_k_recomendacion}
              valor={(x) => <>{f.recomendacion(x.media!)} <small>/ 10</small></>}
              detalle={(x) => t.k_recomendacion_d(f.nps(x.nps!))} />
          </div>

          <div className="en-two" style={{ marginTop: "1.2rem" }}>
            <section className="card">
              <h3>{t.bloques}</h3>
              <p className="en-hint">{t.fam_bloques_lead}</p>
              {datos.bloques.map(({ bloque, fila }) => <Barra key={bloque.codigo} etiqueta={bloque.nombre} fila={fila} />)}
            </section>
            {datos.porEtapa.length > 0 ? (
              <section className="card">
                <h3>{t.fam_general_etapa}</h3>
                <p className="en-hint">{t.fam_general_etapa_lead}</p>
                {datos.porEtapa.map((p) => <Barra key={p.clave.etapa} etiqueta={t.etapas[p.clave.etapa as Etapa]} fila={p} />)}
              </section>
            ) : (
              <section className="card">
                <h3>{t.valorado}</h3>
                <p className="en-hint">{t.valorado_lead}</p>
                <Ranking fila={datos.valorado} textos={textos} />
              </section>
            )}
          </div>

          <h2 className="section-title">{t.detalle}</h2>
          <p className="sec-lead">{t.detalle_lead}</p>
          <div className="card">
            <div className="en-toolbar en-noprint">
              <label className="en-filters" style={{ display: "grid" }}>
                <span>{t.bloque}</span>
                <span className="en-select">
                  <select value={bloqueDetalle} onChange={(e) => setBloqueDetalle(e.target.value)}>
                    {datos.bloques.map(({ bloque }) => <option key={bloque.codigo} value={bloque.codigo}>{bloque.nombre}</option>)}
                  </select>
                </span>
              </label>
            </div>
            <LeyendaAcuerdo etiquetas={etiquetas} />
            <CabeceraPreguntas />
            {!detalle ? <p className="en-cargando">{t.cargando}</p>
              : detalle.map((d) => <FilaPregunta key={d.codigo} texto={d.texto} fila={d.resultado.total} etiquetas={etiquetas} />)}
          </div>

          <h2 className="section-title">{t.recomendacion}</h2>
          <p className="sec-lead">{t.recomendacion_lead("1 a 10")}</p>
          <Recomendacion fila={datos.recomendacion} desde={1} />

          {datos.porEtapa.length > 0 && (
            <>
              <h2 className="section-title">{t.valorado}</h2>
              <p className="sec-lead">{t.valorado_lead}</p>
              <div className="card"><Ranking fila={datos.valorado} textos={textos} /></div>
            </>
          )}

          <p className="notice" style={{ marginTop: "1.4rem" }}>{t.fam_aviso_etapas} {t.leyenda_oculto}</p>
        </>
      )}
    </div>
  );
}

/** Nota de familias sin etapa con el criterio de las partes ocultas (§5.6): nunca el número
 *  exacto si la parte está oculta. */
function notaSinEtapa(p: Fila): string {
  if (!p.suprimido) return t.sin_etapa_n(f.recuento(p.n!));
  return p.motivo === "menos_de_5" ? t.sin_etapa_menos5 : t.sin_etapa_5omas;
}
