// Panel general (§7.1): indicadores por colectivo, recomendación comparada con las barras de
// reparto (§7.8), preguntas comunes y lo más valorado. La coordinación solo ve alumnos y
// familias de su etapa, sin personal.

import { useEffect, useState } from "react";
import { useAyuda } from "../componentes/Ayuda";
import { BarraReparto, lineasOculto, textoReparto } from "../componentes/Graficos";
import { Migas } from "../componentes/Marco";
import { Oculto } from "../componentes/Oculto";
import {
  comparacionRecomendacion, opciones, preguntasComunes, puntosColectivo, resultados,
  type BloqueComparado, type Colectivo, type Fila, type Filtro, type PreguntaComun, type Punto,
} from "../data/resultados";
import type { Perfil } from "../data/sesion";
import * as f from "../formato";
import { t } from "../i18n";

const CLASE: Record<Colectivo, string> = { alumnos: "en-p1", familias: "en-p2", personal: "en-p3" };

interface Indicadores { personas: Fila; principal: Fila; etiquetaPrincipal: string }
interface FilaRec { etiqueta: string; fila: Fila; escala: string }
interface Comun { pregunta: PreguntaComun; valores: Partial<Record<Colectivo, Fila>> }

export function Panel({ perfil }: { perfil: Perfil }) {
  const coordinacion = perfil.rol === "coordinacion";
  const colectivos: Colectivo[] = coordinacion ? ["alumnos", "familias"] : ["alumnos", "familias", "personal"];
  const [indicadores, setIndicadores] = useState<Partial<Record<Colectivo, Indicadores>>>({});
  const [rec, setRec] = useState<FilaRec[] | null>(null);
  const [comunes, setComunes] = useState<Comun[] | null>(null);
  const [valorado, setValorado] = useState<Partial<Record<Colectivo, Fila>>>({});
  const [textos, setTextos] = useState<Record<string, string>>({});
  const [puntos, setPuntos] = useState<Partial<Record<Colectivo, { mejora: Punto[]; fuertes: Punto[] }>>>({});
  const [dif, setDif] = useState<Partial<Record<Colectivo, BloqueComparado[]>>>({});
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let vigente = true;
    // Una coordinación sin encuesta de alumnos (Infantil) no tiene ese colectivo.
    const seguro = (p: Promise<{ total: Fila }>) => p.then((r) => r.total).catch(() => null);
    (async () => {
      const filtro = (c: Colectivo): Filtro => ({ colectivo: c });
      const [ind, recs, lista, val, txt] = await Promise.all([
        Promise.all(colectivos.map(async (c) => {
          const principal = c === "alumnos" ? { tipo: "bloque" as const, codigo: "satisfaccion_general" }
            : c === "familias" ? { tipo: "bloque" as const, codigo: "general" } : { tipo: "satisfaccion" as const };
          const [personas, p] = await Promise.all([seguro(resultados(filtro(c), { tipo: "personas" })), seguro(resultados(filtro(c), principal))]);
          return [c, personas && p ? { personas, principal: p, etiquetaPrincipal: t.panel_principal[c] } : null] as const;
        })),
        Promise.all([
          ...(coordinacion
            ? [seguro(resultados({ colectivo: "alumnos" }, { tipo: "recomendacion" })).then((fila) => fila && {
                etiqueta: t.panel_rec_alumnos_etapa(t.etapas[perfil.etapa as keyof typeof t.etapas]), fila,
                escala: perfil.etapa === "primaria" ? "1 a 10" : "0 a 10" })]
            : [
                seguro(resultados({ colectivo: "alumnos", etapa: "primaria" }, { tipo: "recomendacion" }))
                  .then((fila) => fila && { etiqueta: t.panel_rec_primaria, fila, escala: "1 a 10" }),
                seguro(resultados({ colectivo: "alumnos", etapas: ["pai", "bachillerato"] }, { tipo: "recomendacion" }))
                  .then((fila) => fila && { etiqueta: t.panel_rec_pai_bach, fila, escala: "0 a 10" }),
              ]),
          seguro(resultados({ colectivo: "familias" }, { tipo: "recomendacion" })).then((fila) => fila && { etiqueta: t.fam_titulo, fila, escala: "1 a 10" }),
          ...(coordinacion ? [] : [seguro(resultados({ colectivo: "personal" }, { tipo: "recomendacion" }))
            .then((fila) => fila && { etiqueta: t.per_titulo, fila, escala: "1 a 10" })]),
        ]),
        preguntasComunes(),
        Promise.all(colectivos.map(async (c) => [c, await seguro(resultados(filtro(c), { tipo: "seleccion", codigo: "mas_valorado" }))] as const)),
        opciones("mas_valorado"),
      ]);
      const [pts, difs] = await Promise.all([
        Promise.all(colectivos.map(async (c) => [c, await puntosColectivo(c).catch(() => null)] as const)),
        coordinacion ? Promise.resolve([]) : Promise.all(colectivos.map(async (c) => [c, await comparacionRecomendacion(c).catch(() => null)] as const)),
      ]);
      const valores = await Promise.all(lista.map(async (p) => {
        const pares = await Promise.all(colectivos.filter((c) => p.preguntas[c]).map(async (c) =>
          [c, await seguro(resultados(filtro(c), { tipo: "pregunta", codigo: p.preguntas[c]! }))] as const));
        return { pregunta: p, valores: Object.fromEntries(pares.filter(([, v]) => v)) as Comun["valores"] };
      }));
      if (!vigente) return;
      setIndicadores(Object.fromEntries(ind.filter(([, v]) => v)) as Partial<Record<Colectivo, Indicadores>>);
      setRec(recs.filter((r): r is FilaRec => !!r));
      // Solo las preguntas que se pueden comparar: al menos dos colectivos visibles.
      setComunes(valores.filter((v) => Object.keys(v.valores).length >= 2));
      setValorado(Object.fromEntries(val.filter(([, v]) => v)) as Partial<Record<Colectivo, Fila>>);
      setTextos(txt);
      setPuntos(Object.fromEntries(pts.filter(([, v]) => v)) as Partial<Record<Colectivo, { mejora: Punto[]; fuertes: Punto[] }>>);
      setDif(Object.fromEntries(difs.filter(([, v]) => v && v.length)) as Partial<Record<Colectivo, BloqueComparado[]>>);
    })().catch(() => vigente && setError(t.error_datos));
    return () => { vigente = false; };
  }, [perfil]);

  return (
    <div className="page">
      <Migas actual={t.nav_panel} />
      <p className="eyebrow">{t.alu_eyebrow}</p>
      <h1>📊 {t.nav_panel}</h1>
      <p className="lead">{coordinacion ? t.panel_lead_coord : t.panel_lead}</p>

      {error && <p className="notice">{error}</p>}
      {!rec && !error && <p className="en-cargando">{t.cargando}</p>}
      {rec && comunes && (
        <>
          <h2 className="section-title">{t.panel_indicadores}</h2>
          <p className="sec-lead">{t.panel_indicadores_lead}</p>
          <div className="tiles cols3">
            {colectivos.filter((c) => indicadores[c]).map((c) => (
              <a key={c} className="tile en-tile" href={`#/${c}`}>
                <span className="t-em">{t.panel_emoji[c]}</span>
                <span className="t-b">
                  <strong>{t.panel_colectivo[c]}</strong>
                  <small>
                    {indicadores[c]!.personas.suprimido ? <Oculto fila={indicadores[c]!.personas} /> : `${f.recuento(indicadores[c]!.personas.n!)} ${t.respuestas}`}
                    {" · "}{indicadores[c]!.etiquetaPrincipal}{" "}
                    {indicadores[c]!.principal.suprimido ? <Oculto fila={indicadores[c]!.principal} /> : <b>{f.media(indicadores[c]!.principal.media!)} / 6</b>}
                  </small>
                </span>
                <span className="t-go">→</span>
              </a>
            ))}
          </div>

          <h2 className="section-title">{t.panel_rec}</h2>
          <p className="sec-lead">{t.panel_rec_lead}</p>
          <div className="card">
            {rec.map((r) => <FilaReparto key={r.etiqueta} {...r} />)}
            <details className="en-calculo" style={{ marginTop: ".8rem" }}>
              <summary>{t.como_se_calcula}</summary>
              <p>{t.calculo_reparto}</p>
              <p>{t.calculo_indice}</p>
              <p>{t.panel_rec_escalas}</p>
            </details>
          </div>

          <h2 className="section-title">{t.panel_puntos}</h2>
          <p className="sec-lead">{t.panel_puntos_lead}</p>
          <div className="en-puntos">
            {colectivos.filter((c) => puntos[c]).map((c) => (
              <div key={c} className="card">
                <h3><i className={`en-punto-color ${CLASE[c]}`} aria-hidden="true" />{t.panel_colectivo[c]}</h3>
                <ListaPuntos titulo={t.panel_mejora} puntos={puntos[c]!.mejora} clase="en-mejora" />
                <ListaPuntos titulo={t.panel_fuertes} puntos={puntos[c]!.fuertes} clase="en-fuerte" />
              </div>
            ))}
          </div>

          {colectivos.some((c) => dif[c]) && (
            <>
              <h2 className="section-title">{t.panel_dif}</h2>
              <p className="sec-lead">{t.panel_dif_lead}</p>
              <div className="card">
                <div className="en-legend">
                  <span><i className="en-dif-no" />{t.panel_dif_no}</span>
                  <span><i className="en-dif-si" />{t.panel_dif_si}</span>
                </div>
                {colectivos.filter((c) => dif[c]).map((c) => (
                  <div key={c} className="en-dif-colectivo">
                    <h3>{t.panel_colectivo[c]}</h3>
                    {dif[c]!.map((b) => <BloqueDif key={b.bloque} b={b} />)}
                  </div>
                ))}
                <p className="notice" style={{ marginTop: ".8rem" }}>{t.panel_dif_nota}</p>
              </div>
            </>
          )}

          <h2 className="section-title">{t.panel_comunes}</h2>
          <p className="sec-lead">{t.panel_comunes_lead}</p>
          <div className="card">
            <div className="en-legend">
              {colectivos.map((c) => <span key={c}><i className={CLASE[c]} />{t.panel_colectivo[c]}</span>)}
            </div>
            {comunes.map((c) => <PreguntaComparada key={c.pregunta.codigo} comun={c} colectivos={colectivos} />)}
            <p className="en-hint" style={{ marginTop: ".8rem" }}>{t.panel_comunes_nota}</p>
          </div>

          <h2 className="section-title">{t.valorado}</h2>
          <p className="sec-lead">{t.panel_valorado_lead}</p>
          <div className="card">
            <div className="en-legend">
              {colectivos.filter((c) => valorado[c]).map((c) => <span key={c}><i className={CLASE[c]} />{t.panel_colectivo[c]}</span>)}
            </div>
            <ValoradoComparado valorado={valorado} textos={textos} colectivos={colectivos} />
          </div>

          <h2 className="section-title">{t.panel_menos}</h2>
          <p className="sec-lead">{t.panel_menos_lead}</p>
          <div className="en-puntos">
            {colectivos.filter((c) => valorado[c] && !valorado[c]!.suprimido).map((c) => (
              <div key={c} className="card">
                <h3><i className={`en-punto-color ${CLASE[c]}`} aria-hidden="true" />{t.panel_colectivo[c]}</h3>
                <ol className="en-lista-puntos">
                  {[...(valorado[c]!.opciones ?? [])].filter((o) => o.n > 0).sort((a, b) => a.pct - b.pct).slice(0, 5).map((o) => (
                    <li key={o.codigo}><span>{textos[o.codigo] ?? o.codigo}</span><b>{f.porcentaje(o.pct)}</b></li>
                  ))}
                </ol>
              </div>
            ))}
          </div>
          <p className="notice">{t.panel_menos_nota}</p>

          <p className="notice" style={{ marginTop: "1.4rem" }}>{t.leyenda_oculto} {t.aviso_cierre}</p>
        </>
      )}
    </div>
  );
}

function FilaReparto({ etiqueta, fila, escala }: FilaRec) {
  const ayuda = useAyuda();
  return (
    <div className="en-rep">
      <div className="en-rep-cab">
        <strong>{etiqueta}</strong>
        {fila.suprimido ? <Oculto fila={fila} />
          : <span className="en-con-ayuda" {...ayuda([t.indice, t.indice_explicacion])}>{t.indice} <b>{f.nps(fila.nps!)}</b> · {f.recuento(fila.n!)} {t.respuestas} · {t.escala_de(escala)}</span>}
      </div>
      {fila.suprimido ? <p className="en-hint">{lineasOculto(fila)}</p> : (
        <>
          <BarraReparto fila={fila} />
          <div className="en-reparto">{textoReparto(fila)}</div>
        </>
      )}
    </div>
  );
}

function PreguntaComparada({ comun, colectivos }: { comun: Comun; colectivos: Colectivo[] }) {
  const ayuda = useAyuda();
  return (
    <div className="en-comun">
      <div className="en-comun-t">{comun.pregunta.texto}</div>
      <div className="en-comun-barras">
        {colectivos.filter((c) => comun.valores[c]).map((c) => {
          const v = comun.valores[c]!;
          const ancho = v.suprimido ? 0 : ((v.media! - 1) / 5) * 100;
          return (
            <div key={c} className="en-comun-fila en-con-ayuda"
                 {...ayuda(v.suprimido ? [comun.pregunta.texto, t.panel_colectivo[c], lineasOculto(v)]
                   : [comun.pregunta.texto, t.panel_colectivo[c], t.tip_media(f.media(v.media!)), t.tip_valoraciones(f.recuento(v.n!))])}>
              <span className="en-track" aria-hidden="true"><span className={`en-fill ${CLASE[c]}`} style={{ width: `${ancho}%` }} /></span>
              <span className="en-val">{v.suprimido ? <Oculto fila={v} /> : f.media(v.media!)}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function ValoradoComparado({ valorado, textos, colectivos }: {
  valorado: Partial<Record<Colectivo, Fila>>; textos: Record<string, string>; colectivos: Colectivo[];
}) {
  const ayuda = useAyuda();
  const visibles = colectivos.filter((c) => valorado[c] && !valorado[c]!.suprimido);
  // Los aspectos más elegidos: los cinco primeros de cada colectivo.
  const codigos = new Set<string>();
  for (const c of visibles) {
    [...(valorado[c]!.opciones ?? [])].sort((a, b) => b.pct - a.pct).slice(0, 5).forEach((o) => codigos.add(o.codigo));
  }
  const pct = (c: Colectivo, codigo: string) => valorado[c]?.opciones?.find((o) => o.codigo === codigo);
  const filas = [...codigos].sort((a, b) =>
    Math.max(...visibles.map((c) => pct(c, b)?.pct ?? 0)) - Math.max(...visibles.map((c) => pct(c, a)?.pct ?? 0)));
  return (
    <>
      {filas.map((codigo) => (
        <div key={codigo} className="en-comun">
          <div className="en-comun-t">{textos[codigo] ?? codigo}</div>
          <div className="en-comun-barras">
            {visibles.map((c) => {
              const o = pct(c, codigo);
              const p = o?.pct ?? 0;
              return (
                <div key={c} className="en-comun-fila en-con-ayuda"
                     {...ayuda([textos[codigo] ?? codigo, t.panel_colectivo[c], f.porcentaje(p), t.tip_eligen(f.recuento(o?.n ?? 0), f.recuento(valorado[c]!.n!))])}>
                  <span className="en-track" aria-hidden="true"><span className={`en-fill ${CLASE[c]}`} style={{ width: `${p}%` }} /></span>
                  <span className="en-val">{f.porcentaje(p)}</span>
                </div>
              );
            })}
          </div>
        </div>
      ))}
    </>
  );
}

function ListaPuntos({ titulo, puntos, clase }: { titulo: string; puntos: Punto[]; clase: string }) {
  return (
    <div className={`en-puntos-bloque ${clase}`}>
      <h4>{titulo}</h4>
      <ol className="en-lista-puntos">
        {puntos.map((p) => (
          <li key={p.codigo}>
            <span>{p.texto}<small>{t.panel_pct_bajo(f.porcentaje(p.pct_bajo))} · {t.tip_valoraciones(f.recuento(p.n))}</small></span>
            <b>{f.media(p.media)}</b>
          </li>
        ))}
      </ol>
    </div>
  );
}

function BloqueDif({ b }: { b: BloqueComparado }) {
  const ancho = (fila: Fila) => (fila.suprimido ? 0 : ((fila.media! - 1) / 5) * 100);
  return (
    <div className="en-comun">
      <div className="en-comun-t">{b.nombre}
        <small className="en-hint" style={{ display: "block" }}>
          {b.diferencia === null ? t.panel_dif_sin : t.panel_dif_valor(f.media(b.diferencia))}
        </small>
      </div>
      <div className="en-comun-barras">
        {([["no_recomienda", "en-dif-no"], ["recomienda", "en-dif-si"]] as const).map(([k, clase]) => (
          <div key={k} className="en-comun-fila">
            <span className="en-track" aria-hidden="true"><span className={`en-fill ${clase}`} style={{ width: `${ancho(b[k])}%` }} /></span>
            <span className="en-val">{b[k].suprimido ? <Oculto fila={b[k]} /> : f.media(b[k].media!)}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
