// PDF de un nivel de «Informes por persona» (§7.0 y §7.3): Dirección, el Equipo de
// Individuación (todo o un tramo) o un jefe de departamento. Una o varias secciones, cada una con
// su media y cada pregunta con su distribución divergente; en el de un jefe, además, la media de
// los profesores de cada uno de sus departamentos según los alumnos.

import { Document, Page, StyleSheet, Text, View } from "@react-pdf/renderer";
import type { DetallePregunta, Fila } from "../data/resultados";
import * as f from "../formato";
import { t } from "../i18n";
import { base, C, Cabecera, MarcaAgua, Pie, textoOculto } from "./comun";
import type { SelloDescarga } from "../exportacion/modelo";

const s = StyleSheet.create({
  kpis: { flexDirection: "row", gap: 8, marginTop: 12 },
  kpi: { flex: 1, borderRadius: 8, padding: 10, backgroundColor: C.navy },
  kpiL: { fontSize: 8, fontWeight: 700, color: "#b9c6d8" },
  kpiV: { fontSize: 18, fontWeight: 800, color: "#ffffff", marginTop: 3 },
  kpiD: { fontSize: 7.5, color: "#b9c6d8", marginTop: 2 },
  kpiSuave: { backgroundColor: C.soft },
  kpiLSuave: { color: C.muted },
  kpiVSuave: { color: C.navy },
  leyenda: { flexDirection: "row", flexWrap: "wrap", gap: 8, marginBottom: 6 },
  leyendaItem: { flexDirection: "row", alignItems: "center", fontSize: 7, color: C.muted },
  cuadro: { width: 7, height: 7, borderRadius: 2, marginRight: 3 },
  fila: { flexDirection: "row", alignItems: "center", paddingVertical: 4, borderBottomWidth: 0.5, borderBottomColor: C.line },
  pregunta: { flex: 1.5, paddingRight: 6 },
  div: { flex: 1, flexDirection: "row", height: 9 },
  mitad: { flex: 1, flexDirection: "row" },
  izq: { justifyContent: "flex-end" },
  centro: { width: 1, backgroundColor: C.line },
  media: { width: 50, textAlign: "right", fontWeight: 700 },
  n: { width: 32, textAlign: "right", color: C.muted, fontSize: 8 },
});


function Divergente({ fila }: { fila: Fila }) {
  const n = fila.n ?? 0;
  const d = [1, 2, 3, 4, 5, 6].map((v) => fila.distribucion?.[String(v)] ?? 0);
  // Tonos de la paleta y la cifra (% de respuestas) dentro del tramo cuando cabe, para no depender solo del color.
  const tramo = (v: number) => {
    const pct = (100 * d[v - 1]) / n;
    return d[v - 1] ? (
      <View key={v} style={{ width: `${pct}%`, backgroundColor: C.escala[v - 1], justifyContent: "center", alignItems: "center" }}>
        {pct >= 9 ? <Text style={{ fontSize: 5.5, fontWeight: 700, color: C.escalaTexto[v - 1] }}>{Math.round(pct)}</Text> : null}
      </View>
    ) : null;
  };
  return (
    <View style={s.div}>
      <View style={[s.mitad, s.izq]}>{[1, 2, 3].map(tramo)}</View>
      <View style={s.centro} />
      <View style={s.mitad}>{[4, 5, 6].map(tramo)}</View>
    </View>
  );
}

export interface SeccionPdf {
  titulo: string;
  subtitulo: string;
  nota?: string;
  etiquetas: string[];
  informe: { total: Fila; preguntas: DetallePregunta[] };
}

/** Media de los profesores de un departamento según los alumnos (§7.0, Departamentos). */
export interface AlumnosDepartamentoPdf {
  titulo?: string;        // «Profesores de Ciencias según los alumnos»
  texto: string;          // «4,52 / 6» o el motivo por el que no hay cifra
  detalle?: string;       // combinaciones y valoraciones
  nota?: string;          // combinaciones excluidas
}

export interface DatosNivelPdf {
  eyebrow: string;
  titulo: string;
  subtitulo: string;
  secciones: SeccionPdf[];
  alumnos?: AlumnosDepartamentoPdf[];
  /** Texto en lugar de las secciones cuando no hay ninguna (departamento sin datos de reuniones). */
  sinSecciones?: string;
  /** Informes de jefatura: completa (Dirección y administración) o la de la jefatura, con el mínimo de 5. Sin versión, el de
   *  Dirección y el de todo el equipo, que solo descargan Dirección y administración. */
  version?: "completa" | "jefatura";
  sello: SelloDescarga;
}

function Seccion({ seccion, primera }: { seccion: SeccionPdf; primera: boolean }) {
  const tot = seccion.informe.total;
  return (
    <View break={!primera && seccion.informe.preguntas.length > 12}>
      <Text style={[base.h2, primera ? { marginTop: 14 } : {}]}>{seccion.titulo}</Text>
      <Text style={base.lead}>{seccion.subtitulo}</Text>
      <View style={s.kpis}>
        <View style={s.kpi}>
          <Text style={s.kpiL}>{t.resp_media_bloque}</Text>
          <Text style={s.kpiV}>{tot.suprimido ? textoOculto(tot) : `${f.media(tot.media!)} / 6`}</Text>
          {!tot.suprimido && <Text style={s.kpiD}>{t.tip_personas(f.recuento(tot.n!))} · {t.tip_valoraciones(f.recuento(tot.n_valoraciones ?? 0))}{tot.menos_de_5 ? ` · ${t.marca_menos5}` : ""}</Text>}
        </View>
      </View>
      {seccion.nota && <Text style={base.aviso}>{seccion.nota}</Text>}
      {!tot.suprimido && (
        <>
          <View style={[s.leyenda, { marginTop: 10 }]}>
            {seccion.etiquetas.map((e, i) => (
              <View key={i} style={s.leyendaItem}><View style={[s.cuadro, { backgroundColor: C.escala[i] }]} /><Text>{i + 1} · {e}</Text></View>
            ))}
          </View>
          {seccion.informe.preguntas.map((p) => {
            const r = p.resultado.total;
            return (
              <View key={p.codigo} style={s.fila} wrap={false}>
                <Text style={s.pregunta}>{p.texto}</Text>
                {r.suprimido ? <View style={s.div} /> : <Divergente fila={r} />}
                <Text style={[s.media, r.suprimido ? base.oculto : {}]}>{r.suprimido ? textoOculto(r) : f.media(r.media!)}</Text>
                <Text style={s.n}>{r.suprimido ? "" : `n ${f.recuento(r.n!)}`}{r.menos_de_5 ? `\n${t.marca_menos5}` : ""}</Text>
              </View>
            );
          })}
        </>
      )}
    </View>
  );
}

export function InformeNivelPdf({ eyebrow, titulo, subtitulo, secciones, alumnos, sinSecciones, version, sello }: DatosNivelPdf) {
  const conMinimo = version === "jefatura";
  const hayComplementaria = secciones.some((x) => x.informe.preguntas.some((p) => p.resultado.total.motivo === "complementaria")
    || x.informe.total.motivo === "complementaria");
  return (
    <Document title={`${eyebrow} · ${titulo}`} author="Colegio Internacional de Sevilla, San Francisco de Paula" subject={t.desc_asunto} language="es">
      <Page size="A4" style={base.pagina}>
        <MarcaAgua />
        <Cabecera subtitulo={version ? `${t.pdf_cab_resp} · ${conMinimo ? t.version_jefatura_corta : t.version_completa_corta}` : t.pdf_cab_resp} />
        <View style={base.cuerpo}>
          <Text style={base.eyebrow}>{eyebrow}</Text>
          <Text style={base.titulo}>{titulo}</Text>
          <Text style={base.muted}>{subtitulo}</Text>
          {version && (
            <Text style={{ marginTop: 6, paddingVertical: 4, paddingHorizontal: 8, borderLeftWidth: 3, borderLeftColor: C.neutro,
                           backgroundColor: C.neutroSuave, fontSize: 8.5, fontWeight: 700, color: C.ink }}>
              {conMinimo ? t.version_jefatura : `${t.version_completa} · ${t.pdf_version_completa_jefatura}`}
            </Text>
          )}

          {secciones.length === 0 && sinSecciones && <Text style={[base.aviso, { marginTop: 14 }]}>{sinSecciones}</Text>}
          {secciones.map((x, i) => <Seccion key={i} seccion={x} primera={i === 0} />)}

          {alumnos?.map((a, i) => (
            <View key={i} wrap={false}>
              <Text style={base.h2}>{a.titulo ?? t.dep_alumnos_titulo}</Text>
              <Text style={base.lead}>{t.dep_alumnos_lead}</Text>
              <View style={s.kpis}>
                <View style={[s.kpi, s.kpiSuave]}>
                  <Text style={[s.kpiL, s.kpiLSuave]}>{t.dep_alumnos_media}</Text>
                  <Text style={[s.kpiV, s.kpiVSuave]}>{a.texto}</Text>
                  {a.detalle && <Text style={[s.kpiD, s.kpiLSuave]}>{a.detalle}</Text>}
                </View>
              </View>
              {a.nota && <Text style={base.aviso}>{a.nota}</Text>}
            </View>
          ))}

          <Text style={[base.nota, { marginTop: 14 }]}>{t.pdf_nota_escala}</Text>
          {/* La versión para la jefatura, con el mínimo de 5; las demás, con el criterio de Dirección (§5.0). */}
          <Text style={base.nota}>{conMinimo ? t.pdf_nota_oculto : t.leyenda_menos5}</Text>
          {hayComplementaria && <Text style={base.nota}>{t.pdf_nota_asterisco}</Text>}
          <Text style={base.nota}>{conMinimo ? t.aviso_cierre : t.aviso_cierre_direccion}</Text>
        </View>
        <Pie sello={sello} />
      </Page>
    </Document>
  );
}
