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

export function Barra({ etiqueta, fila }: { etiqueta: string; fila: Fila }) {
  const ayuda = useAyuda();
  const ancho = fila.suprimido || fila.media == null ? 0 : ((fila.media - 1) / 5) * 100;
  const lineas = fila.suprimido ? [etiqueta, lineasOculto(fila)] : [
    etiqueta,
    t.tip_media(f.media(fila.media!)),
    t.tip_personas(f.recuento(fila.n_personas ?? fila.n!)),
    t.tip_valoraciones(f.recuento(fila.n_valoraciones ?? 0)),
    ...(fila.ns_nc ? [t.tip_nsnc(f.recuento(fila.ns_nc))] : []),
  ];
  return (
    <div className="en-bar en-con-ayuda" {...ayuda(lineas)}>
      <span>{etiqueta}</span>
      <span className="en-track" aria-hidden="true"><span className="en-fill" style={{ width: `${ancho}%` }} /></span>
      <span className="en-val">
        {fila.suprimido ? <Oculto fila={fila} /> : <>{f.media(fila.media!)}<small>n {f.recuento(fila.n!)}</small></>}
      </span>
    </div>
  );
}

export function Recomendacion({ fila, desde }: { fila: Fila; desde: number }) {
  const ayuda = useAyuda();
  if (fila.suprimido) return <div className="card"><Oculto fila={fila} /><p className="en-hint">{lineasOculto(fila)}</p></div>;
  const tramos = [
    { clase: "en-n3", texto: t.detractores, pct: fila.detractores_pct ?? 0, rango: t.rango_detractores },
    { clase: "en-neu", texto: t.neutros, pct: fila.neutros_pct ?? 0, rango: t.rango_neutros },
    { clase: "en-p2", texto: t.promotores, pct: fila.promotores_pct ?? 0, rango: t.rango_promotores },
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
        <div className="en-apilada">
          {tramos.map((x) => (
            <span key={x.clase} className={`${x.clase} en-con-ayuda`} style={{ width: `${x.pct}%` }}
                  {...ayuda([x.texto, f.porcentaje(x.pct), t.tip_de_respuestas(f.recuento(Math.round((x.pct * fila.n!) / 100)), f.recuento(fila.n!)), x.rango])} />
          ))}
        </div>
        <div className="en-legend">
          {tramos.map((x) => <span key={x.clase}><i className={x.clase} />{x.texto} {f.porcentaje(x.pct)}</span>)}
        </div>
      </section>
      <section className="card">
        <h3>{t.distribucion}</h3>
        <p className="en-hint">{t.distribucion_lead}</p>
        <div className="en-cols">
          {dist.map((d) => (
            <div key={d.v} className="en-col en-con-ayuda"
                 {...ayuda([t.tip_puntuacion(d.v), t.tip_de_respuestas(f.recuento(d.n), f.recuento(fila.n!)),
                            f.porcentaje((100 * d.n) / fila.n!), d.v <= 6 ? t.detractores : d.v <= 8 ? t.neutros : t.promotores])}>
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
