// Informes de responsables (§7.3), solo para administración y dirección. Por ámbito, no por
// persona: Equipo de Individualización, cada departamento con 5 o más personas y Superiores
// (personal no docente). Vista y PDF individual.

import { useEffect, useState } from "react";
import { CabeceraPreguntas, FilaPregunta, LeyendaAcuerdo, lineasOculto } from "../componentes/Graficos";
import { Migas } from "../componentes/Marco";
import { Oculto } from "../componentes/Oculto";
import { informeResponsable, resultados, type InformeResponsable, type TipoResponsable } from "../data/resultados";
import * as f from "../formato";
import { t } from "../i18n";

interface Ambito {
  clave: string;
  tipo: TipoResponsable;
  ambito: string | null;
  titulo: string;
  subtitulo: string;
  nota?: string;
  etiquetas: string[];
  emoji: string;
}

export function Responsables() {
  const [ambitos, setAmbitos] = useState<Ambito[] | null>(null);
  const [ocultos, setOcultos] = useState(0);
  const [elegido, setElegido] = useState<Ambito | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    resultados({ colectivo: "personal" }, { tipo: "bloque", codigo: "reuniones_departamento" }, ["departamento"])
      .then((r) => {
        // Solo los departamentos con su resultado visible (5 o más personas) tienen informe.
        const visibles = r.partes.filter((p) => !p.suprimido).map((p) => p.clave.departamento)
          .sort((a, b) => a.localeCompare(b, "es"));
        setOcultos(r.partes.filter((p) => p.suprimido).length);
        const lista: Ambito[] = [
          { clave: "equipo", tipo: "equipo_individualizacion", ambito: null, titulo: t.resp_equipo, subtitulo: t.resp_equipo_sub,
            etiquetas: t.escala_acuerdo_per, emoji: "🧩" },
          ...visibles.map((d): Ambito => ({
            clave: `dep-${d}`, tipo: "departamento", ambito: d, titulo: t.resp_departamento(d), subtitulo: t.resp_departamento_sub,
            etiquetas: t.escala_acuerdo_dep, emoji: "🏫" })),
          { clave: "superiores", tipo: "superiores", ambito: null, titulo: t.resp_superiores, subtitulo: t.resp_superiores_sub,
            nota: t.per_superiores_nota, etiquetas: t.escala_acuerdo_per, emoji: "🧭" },
        ];
        setAmbitos(lista);
        setElegido(lista[0]);
      })
      .catch(() => setError(t.error_datos));
  }, []);

  return (
    <div className="page">
      <Migas actual={t.nav_responsables} />
      <p className="eyebrow">{t.alu_eyebrow}</p>
      <h1>🧭 {t.nav_responsables}</h1>
      <p className="lead">{t.resp_lead}</p>
      {error && <p className="notice">{error}</p>}
      {!ambitos && !error && <p className="en-cargando">{t.cargando}</p>}
      {ambitos && (
        <div className="en-prof">
          <div className="card en-noprint">
            <ul className="en-prof-lista" aria-label={t.resp_lista}>
              {ambitos.map((a) => (
                <li key={a.clave}>
                  <button type="button" className={elegido?.clave === a.clave ? "on" : undefined} aria-pressed={elegido?.clave === a.clave}
                          onClick={() => setElegido(a)}>
                    <strong>{a.emoji} {a.titulo}</strong><small>{a.subtitulo}</small>
                  </button>
                </li>
              ))}
            </ul>
            {ocultos > 0 && <p className="en-hint" style={{ marginTop: ".6rem" }}>{t.resp_ocultos(ocultos)}</p>}
          </div>
          <div>{elegido && <Informe ambito={elegido} />}</div>
        </div>
      )}
      <p className="notice" style={{ marginTop: "1.4rem" }}>{t.resp_aviso} {t.leyenda_oculto}</p>
    </div>
  );
}

function Informe({ ambito }: { ambito: Ambito }) {
  const [datos, setDatos] = useState<InformeResponsable | null>(null);
  const [pdf, setPdf] = useState<"" | "generando" | "error">("");

  useEffect(() => {
    let vigente = true;
    setDatos(null);
    informeResponsable(ambito.tipo, ambito.ambito).then((d) => vigente && setDatos(d)).catch(() => {});
    return () => { vigente = false; };
  }, [ambito.clave]);

  async function generar() {
    setPdf("generando");
    try {
      const { descargarInformeResponsable } = await import("../pdf/generar");
      await descargarInformeResponsable(ambito);
      setPdf("");
    } catch {
      setPdf("error");
    }
  }

  if (!datos) return <p className="en-cargando">{t.cargando}</p>;
  const tot = datos.total;
  return (
    <div className="en-informe">
      <div className="card">
        <p className="eyebrow">{t.resp_informe}</p>
        <h3 className="en-prof-nombre">{ambito.titulo}</h3>
        <p className="en-hint">{ambito.subtitulo}</p>
        <p className="en-noprint">
          <button type="button" className="btn primary" onClick={generar} disabled={pdf === "generando"}>
            📄 {pdf === "generando" ? t.pdf_generando : t.pdf_descargar}
          </button>
          {pdf === "error" && <span className="en-error" role="alert"> {t.pdf_error}</span>}
        </p>
        <div className="en-kpis en-kpis3">
          <div className="card en-kpi hl">
            <div className="l">{t.resp_media_bloque}</div>
            <div className="v">{tot.suprimido ? <Oculto fila={tot} /> : <>{f.media(tot.media!)} <small>/ 6</small></>}</div>
            <div className="d">{tot.suprimido ? lineasOculto(tot) : t.tip_personas(f.recuento(tot.n!))}</div>
          </div>
        </div>
        {ambito.nota && <p className="notice" style={{ marginTop: ".9rem" }}>{ambito.nota}</p>}
      </div>
      {!tot.suprimido && (
        <div className="card" style={{ marginTop: ".9rem" }}>
          <h3>{t.prof_detalle}</h3>
          <p className="en-hint">{t.detalle_lead}</p>
          <LeyendaAcuerdo etiquetas={ambito.etiquetas} />
          <CabeceraPreguntas />
          {datos.preguntas.map((p) => <FilaPregunta key={p.codigo} texto={p.texto} fila={p.resultado.total} etiquetas={ambito.etiquetas} />)}
        </div>
      )}
    </div>
  );
}
