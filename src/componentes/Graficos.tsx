// Gráficos compartidos por las vistas: indicadores, barras de 1 a 6, recomendación y
// distribución. Todos muestran información emergente y respetan los resultados ocultos.

import type { ReactNode } from "react";
import { useAyuda } from "./Ayuda";
import { Oculto } from "./Oculto";
import type { Fila } from "../data/resultados";
import * as f from "../formato";
import { t } from "../i18n";

export function ordenar(filas: Fila[]): Fila[] {
  // Visibles de mayor a menor media; las ocultas al final, sin revelar orden por valor.
  return [...filas].sort((a, b) =>
    a.suprimido !== b.suprimido ? (a.suprimido ? 1 : -1)
      : a.suprimido ? 0 : (b.media ?? 0) - (a.media ?? 0));
}

export function Indicador({ etiqueta, fila, valor, detalle, destacado, explicacion }: {
  etiqueta: string; fila: Fila; valor: (x: Fila) => ReactNode; detalle: (x: Fila) => string; destacado?: boolean;
  explicacion: string;
}) {
  const ayuda = useAyuda();
  return (
    <div className={`card en-kpi en-con-ayuda${destacado ? " hl" : ""}`}
         {...ayuda([etiqueta, fila.suprimido ? lineasOculto(fila) : explicacion])}>
      <div className="l">{etiqueta}</div>
      <div className="v">{fila.suprimido ? <Oculto fila={fila} /> : valor(fila)}</div>
      <div className="d">{fila.suprimido ? "" : detalle(fila)}</div>
    </div>
  );
}

export function lineasOculto(fila: Fila): string {
  return fila.motivo === "menos_de_5" ? t.oculto_tip_menos5 : fila.motivo === "sin_datos" ? t.sin_datos : t.oculto_tip;
}

/** Barra de 1 a 6. Con referencia (coordinación en Familias), una marca con la media de todo el colegio. */
export function Barra({ etiqueta, fila, referencia }: { etiqueta: string; fila: Fila; referencia?: Fila }) {
  const ayuda = useAyuda();
  const ancho = fila.suprimido || fila.media == null ? 0 : ((fila.media - 1) / 5) * 100;
  const ref = referencia && !referencia.suprimido && referencia.media != null ? referencia.media : null;
  const lineas = fila.suprimido ? [etiqueta, lineasOculto(fila)] : [
    etiqueta,
    t.tip_media(f.media(fila.media!)),
    t.tip_personas(f.recuento(fila.n_personas ?? fila.n!)),
    t.tip_valoraciones(f.recuento(fila.n_valoraciones ?? 0)),
    ...(fila.ns_nc ? [t.tip_nsnc(f.recuento(fila.ns_nc))] : []),
  ];
  if (ref != null) lineas.push(t.tip_referencia_colegio(f.media(ref)));
  return (
    <div className="en-bar en-con-ayuda" {...ayuda(lineas)}>
      <span>{etiqueta}</span>
      <span className="en-track" aria-hidden="true">
        <span className="en-fill" style={{ width: `${ancho}%` }} />
        {ref != null && <span className="en-ref" style={{ left: `${((ref - 1) / 5) * 100}%` }} />}
      </span>
      <span className="en-val">
        {fila.suprimido ? <Oculto fila={fila} /> : <>{f.media(fila.media!)}<small>n {f.recuento(fila.n!)}</small></>}
        {ref != null && <small className="en-ref-txt">{t.colegio_corto} {f.media(ref)}</small>}
      </span>
    </div>
  );
}

/** Reparto de la recomendación en tres tramos, en el orden del texto: sí, neutral y no. */
export function tramosRecomendacion(fila: Fila) {
  return [
    { clase: "en-rec-si", corto: t.rec_si, rango: t.rango_promotores, pct: fila.promotores_pct ?? 0 },
    { clase: "en-rec-neutral", corto: t.rec_neutral, rango: t.rango_neutros, pct: fila.neutros_pct ?? 0 },
    { clase: "en-rec-no", corto: t.rec_no, rango: t.rango_detractores, pct: fila.detractores_pct ?? 0 },
  ];
}

/** «X % sí, con entusiasmo (9 y 10) · X % neutral (7 y 8) · X % no (6 o menos)» */
export function textoReparto(fila: Fila): string {
  return tramosRecomendacion(fila).map((x) => `${f.porcentaje(x.pct)} ${x.corto}`).join(" · ");
}

/** Barra de tres colores con información emergente en cada tramo. */
export function BarraReparto({ fila, fina }: { fila: Fila; fina?: boolean }) {
  const ayuda = useAyuda();
  return (
    <div className={`en-apilada${fina ? " fina" : ""}`}>
      {tramosRecomendacion(fila).map((x) => (
        <span key={x.clase} className={`${x.clase} en-cifra en-con-ayuda`} style={{ width: `${x.pct}%` }}
              {...ayuda([`${f.porcentaje(x.pct)} ${x.corto}`, t.tip_de_respuestas(f.recuento(Math.round((x.pct * fila.n!) / 100)), f.recuento(fila.n!)), x.rango])}>
          {!fina && x.pct >= 8 ? f.porcentaje(x.pct) : null}
        </span>
      ))}
    </div>
  );
}

/** Indicador de recomendación: el reparto es el dato principal; el índice, secundario. */
export function IndicadorRecomendacion({ etiqueta, fila }: { etiqueta: string; fila: Fila }) {
  const ayuda = useAyuda();
  if (fila.suprimido) {
    return (
      <div className="card en-kpi en-con-ayuda" {...ayuda([etiqueta, lineasOculto(fila)])}>
        <div className="l">{etiqueta}</div><div className="v"><Oculto fila={fila} /></div>
      </div>
    );
  }
  return (
    <div className="card en-kpi en-kpi-rec">
      <div className="l">{etiqueta}</div>
      <BarraReparto fila={fila} fina />
      <div className="en-reparto">{textoReparto(fila)}</div>
      <div className="d en-con-ayuda" {...ayuda([t.indice, t.indice_explicacion])}>
        {t.indice} <strong>{f.nps(fila.nps!)}</strong>
      </div>
    </div>
  );
}

/** Sección de recomendación: reparto (principal), índice con su explicación (secundario),
 *  distribución de puntuaciones y «Cómo se calcula». */
export function Recomendacion({ fila, desde }: { fila: Fila; desde: number }) {
  const ayuda = useAyuda();
  if (fila.suprimido) return <div className="card"><Oculto fila={fila} /><p className="en-hint">{lineasOculto(fila)}</p></div>;
  const dist = Object.entries(fila.distribucion ?? {})
    .map(([v, n]) => ({ v: Number(v), n }))
    .filter((d) => d.v >= desde)
    .sort((a, b) => a.v - b.v);
  const max = Math.max(1, ...dist.map((d) => d.n));
  const clase = (v: number) => (v <= 6 ? "en-rec-no" : v <= 8 ? "en-rec-neutral" : "en-rec-si");
  const tramo = (v: number) => (v <= 6 ? t.rec_no : v <= 8 ? t.rec_neutral : t.rec_si);
  return (
    <div className="en-two">
      <section className="card">
        <h3>{t.reparto_titulo}</h3>
        <p className="en-hint">{f.recuento(fila.n!)} {t.respuestas}</p>
        <BarraReparto fila={fila} />
        <p className="en-reparto grande">{textoReparto(fila)}</p>
        <div className="en-indice">
          <span>{t.indice}</span> <strong>{f.nps(fila.nps!)}</strong>
          <p>{t.indice_explicacion}</p>
        </div>
        <p className="en-hint">{t.media} {f.recomendacion(fila.media!)} / 10</p>
        <details className="en-calculo">
          <summary>{t.como_se_calcula}</summary>
          <p>{t.calculo_reparto}</p>
          <p>{t.calculo_indice}</p>
        </details>
      </section>
      <section className="card">
        <h3>{t.distribucion}</h3>
        <p className="en-hint">{t.distribucion_lead}</p>
        <div className="en-cols">
          {dist.map((d) => (
            <div key={d.v} className="en-col en-con-ayuda"
                 {...ayuda([t.tip_puntuacion(d.v), t.tip_de_respuestas(f.recuento(d.n), f.recuento(fila.n!)),
                            f.porcentaje((100 * d.n) / fila.n!), tramo(d.v)])}>
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

// Tonos de la paleta (src/paleta.ts): 1 a 3 en negativo, más intenso en el 1; 4 a 6 en positivo, más intenso en el 6.
const TRAMOS_DESACUERDO = ["en-esc-1", "en-esc-2", "en-esc-3"];   // 1, 2, 3
const TRAMOS_ACUERDO = ["en-esc-4", "en-esc-5", "en-esc-6"];       // 4, 5, 6

/** Una pregunta de 1 a 6 con su distribución divergente: desacuerdo a la izquierda (1 a 3) y
 *  acuerdo a la derecha (4 a 6). */
export function FilaPregunta({ texto: guardado, fila, etiquetas }: { texto: string; fila: Fila; etiquetas: string[] }) {
  const ayuda = useAyuda();
  const texto = f.mayusculaInicial(guardado);
  if (fila.suprimido) {
    return (
      <div className="en-item en-con-ayuda" {...ayuda([texto, lineasOculto(fila)])}>
        <span>{texto}</span><span /><span className="n"><Oculto fila={fila} /></span><span /><span />
      </div>
    );
  }
  const n = fila.n!;
  const dist = [1, 2, 3, 4, 5, 6].map((v) => fila.distribucion?.[String(v)] ?? 0);
  const tramo = (v: number, clase: string) => {
    const c = dist[v - 1];
    if (!c) return null;
    return (
      <span key={v} className={`s ${clase} en-cifra`} style={{ width: `${(100 * c) / n}%` }}>
        {(100 * c) / n >= 9 ? Math.round((100 * c) / n) : null}
      </span>
    );
  };
  const lineas = [
    texto,
    t.tip_media(f.media(fila.media!)),
    ...dist.map((c, i) => `${i + 1} · ${etiquetas[i] ?? ""}: ${f.recuento(c)} (${f.porcentaje((100 * c) / n)})`),
    ...(fila.ns_nc ? [t.tip_nsnc(f.recuento(fila.ns_nc))] : []),
  ];
  return (
    <div className="en-item en-con-ayuda" {...ayuda(lineas)}>
      <span>{texto}</span>
      <span className="en-div" aria-hidden="true">
        <span className="h l">{[1, 2, 3].map((v) => tramo(v, TRAMOS_DESACUERDO[v - 1]))}</span>
        <span className="m" />
        <span className="h r">{[4, 5, 6].map((v) => tramo(v, TRAMOS_ACUERDO[v - 4]))}</span>
      </span>
      <span className="n"><strong>{f.media(fila.media!)}</strong></span>
      <span className="n">{f.recuento(n)}</span>
      <span className="n">{fila.ns_nc ? f.recuento(fila.ns_nc) : ""}</span>
    </div>
  );
}

export function CabeceraPreguntas() {
  return (
    <div className="en-item head" aria-hidden="true">
      <span>{t.pregunta}</span><span>{t.distribucion_corta}</span><span className="n">{t.media}</span>
      <span className="n">n</span><span className="n">NS/NC</span>
    </div>
  );
}

export function LeyendaAcuerdo({ etiquetas }: { etiquetas: string[] }) {
  const clases = [...TRAMOS_DESACUERDO, ...TRAMOS_ACUERDO];
  return (
    <div className="en-legend">
      {etiquetas.map((e, i) => <span key={i}><i className={clases[i]} />{i + 1} · {e}</span>)}
      <span className="en-hint-cifras">{t.leyenda_cifras}</span>
    </div>
  );
}

/** «Aspectos más destacados»: porcentaje de personas que eligen cada aspecto. */
export function Ranking({ fila, textos, maximo = 10 }: { fila: Fila; textos: Record<string, string>; maximo?: number }) {
  const ayuda = useAyuda();
  if (fila.suprimido) return <p className="en-hint"><Oculto fila={fila} /> · {lineasOculto(fila)}</p>;
  const ops = [...(fila.opciones ?? [])].filter((o) => o.n > 0).sort((a, b) => b.n - a.n).slice(0, maximo);
  const tope = Math.max(1, ...ops.map((o) => o.pct));
  return (
    <>
      {ops.map((o) => {
        const texto = f.mayusculaInicial(textos[o.codigo] ?? o.codigo);
        return (
          <div key={o.codigo} className="en-bar en-con-ayuda"
               {...ayuda([texto, f.porcentaje(o.pct), t.tip_eligen(f.recuento(o.n), f.recuento(fila.n!))])}>
            <span>{texto}</span>
            <span className="en-track" aria-hidden="true"><span className="en-fill" style={{ width: `${(100 * o.pct) / tope}%` }} /></span>
            <span className="en-val">{f.porcentaje(o.pct)}</span>
          </div>
        );
      })}
    </>
  );
}
