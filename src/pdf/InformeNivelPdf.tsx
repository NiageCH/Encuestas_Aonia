// PDF de un nivel de «Informes por persona» (§7.0 y §7.3): Dirección, Equipos o un
// departamento. Una o varias secciones, cada una con su media y cada pregunta con su
// distribución divergente; en los departamentos, además, la media de sus profesores según los
// alumnos.

import { Document, Page, StyleSheet, Text, View } from "@react-pdf/renderer";
import type { Fila, InformeResponsable } from "../data/resultados";
import * as f from "../formato";
import { t } from "../i18n";
import { base, C, Cabecera, Pie, textoOculto } from "./comun";

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
  div: { flex: 1, flexDirection: "row", height: 8 },
  mitad: { flex: 1, flexDirection: "row" },
  izq: { justifyContent: "flex-end" },
  centro: { width: 1, backgroundColor: C.line },
  media: { width: 50, textAlign: "right", fontWeight: 700 },
  n: { width: 32, textAlign: "right", color: C.muted, fontSize: 8 },
});

const COLORES = [C.n3, C.n2, C.n1, C.p1, C.p2, C.p3];   // 1 a 6

function Divergente({ fila }: { fila: Fila }) {
  const n = fila.n ?? 0;
  const d = [1, 2, 3, 4, 5, 6].map((v) => fila.distribucion?.[String(v)] ?? 0);
  const tramo = (v: number) => d[v - 1] ? <View key={v} style={{ width: `${(100 * d[v - 1]) / n}%`, backgroundColor: COLORES[v - 1] }} /> : null;
  return (
    <View style={s.div}>
      <View style={[s.mitad, s.izq]}>{[3, 2, 1].map(tramo)}</View>
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
  informe: InformeResponsable;
}

/** Media de los profesores de un departamento según los alumnos (§7.0, Departamentos). */
export interface AlumnosDepartamentoPdf {
  texto: string;          // «4,52 / 6» o el motivo por el que no hay cifra
  detalle?: string;       // combinaciones y valoraciones
  nota?: string;          // combinaciones excluidas
}

export interface DatosNivelPdf {
  eyebrow: string;
  titulo: string;
  subtitulo: string;
  secciones: SeccionPdf[];
  alumnos?: AlumnosDepartamentoPdf;
  generado: Date;
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
          {!tot.suprimido && <Text style={s.kpiD}>{t.tip_personas(f.recuento(tot.n!))} · {t.tip_valoraciones(f.recuento(tot.n_valoraciones ?? 0))}</Text>}
        </View>
      </View>
      {seccion.nota && <Text style={base.aviso}>{seccion.nota}</Text>}
      {!tot.suprimido && (
        <>
          <View style={[s.leyenda, { marginTop: 10 }]}>
            {seccion.etiquetas.map((e, i) => (
              <View key={i} style={s.leyendaItem}><View style={[s.cuadro, { backgroundColor: COLORES[i] }]} /><Text>{i + 1} · {e}</Text></View>
            ))}
          </View>
          {seccion.informe.preguntas.map((p) => {
            const r = p.resultado.total;
            return (
              <View key={p.codigo} style={s.fila} wrap={false}>
                <Text style={s.pregunta}>{p.texto}</Text>
                {r.suprimido ? <View style={s.div} /> : <Divergente fila={r} />}
                <Text style={[s.media, r.suprimido ? base.oculto : {}]}>{r.suprimido ? textoOculto(r) : f.media(r.media!)}</Text>
                <Text style={s.n}>{r.suprimido ? "" : `n ${f.recuento(r.n!)}`}</Text>
              </View>
            );
          })}
        </>
      )}
    </View>
  );
}

export function InformeNivelPdf({ eyebrow, titulo, subtitulo, secciones, alumnos, generado }: DatosNivelPdf) {
  const hayComplementaria = secciones.some((x) => x.informe.preguntas.some((p) => p.resultado.total.motivo === "complementaria")
    || x.informe.total.motivo === "complementaria");
  return (
    <Document title={`${eyebrow} · ${titulo}`} author="Colegio Internacional de Sevilla – San Francisco de Paula" language="es">
      <Page size="A4" style={base.pagina}>
        <Cabecera subtitulo={t.pdf_cab_resp} />
        <View style={base.cuerpo}>
          <Text style={base.eyebrow}>{eyebrow}</Text>
          <Text style={base.titulo}>{titulo}</Text>
          <Text style={base.muted}>{subtitulo}</Text>

          {secciones.map((x, i) => <Seccion key={i} seccion={x} primera={i === 0} />)}

          {alumnos && (
            <View wrap={false}>
              <Text style={base.h2}>{t.dep_alumnos_titulo}</Text>
              <Text style={base.lead}>{t.dep_alumnos_lead}</Text>
              <View style={s.kpis}>
                <View style={[s.kpi, s.kpiSuave]}>
                  <Text style={[s.kpiL, s.kpiLSuave]}>{t.dep_alumnos_media}</Text>
                  <Text style={[s.kpiV, s.kpiVSuave]}>{alumnos.texto}</Text>
                  {alumnos.detalle && <Text style={s.kpiD}>{alumnos.detalle}</Text>}
                </View>
              </View>
              {alumnos.nota && <Text style={base.aviso}>{alumnos.nota}</Text>}
            </View>
          )}

          <Text style={[base.nota, { marginTop: 14 }]}>{t.pdf_nota_escala}</Text>
          <Text style={base.nota}>{t.pdf_nota_oculto}{hayComplementaria ? ` ${t.pdf_nota_asterisco}` : ""}</Text>
          <Text style={base.nota}>{t.aviso_cierre}</Text>
        </View>
        <Pie generado={generado} />
      </Page>
    </Document>
  );
}
