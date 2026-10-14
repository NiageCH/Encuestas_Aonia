// Informe PDF por profesor (§7.2), con el estilo de la intranet (§8): logo, colores y
// tipografía. Mismos datos y mismas reglas que la vista: viene de la RPC informe_profesor.

import { Document, Font, Image, Page, StyleSheet, Text, View } from "@react-pdf/renderer";
import type { Style } from "@react-pdf/types";
import type { Fila, InformeProfesor } from "../data/resultados";
import * as f from "../formato";
import { t } from "../i18n";
import logoBlanco from "../recursos/pdf/logo-blanco.png";
import r400 from "../recursos/pdf/Raleway-400.ttf";
import r600 from "../recursos/pdf/Raleway-600.ttf";
import r700 from "../recursos/pdf/Raleway-700.ttf";
import r800 from "../recursos/pdf/Raleway-800.ttf";

Font.register({
  family: "Raleway",
  fonts: [
    { src: r400, fontWeight: 400 }, { src: r600, fontWeight: 600 },
    { src: r700, fontWeight: 700 }, { src: r800, fontWeight: 800 },
  ],
});
Font.registerHyphenationCallback((palabra) => [palabra]);

// Copia literal de las variables de :root de la intranet (el PDF no lee CSS).
const C = { navy: "#1a2c4a", brand: "#0063a3", sky: "#4495ce", muted: "#5b6573", line: "#dde3ea", soft: "#eaf0f6", bg: "#f2f4f7", ink: "#1a2c4a" };

const s = StyleSheet.create({
  pagina: { fontFamily: "Raleway", fontSize: 9.5, color: C.ink, paddingTop: 0, paddingBottom: 46, paddingHorizontal: 0 },
  cabecera: { backgroundColor: C.navy, paddingVertical: 14, paddingHorizontal: 36, flexDirection: "row", alignItems: "center", justifyContent: "space-between" },
  logo: { width: 120, height: 42 },
  cabTexto: { color: "#ffffff", textAlign: "right" },
  cabTitulo: { fontSize: 11, fontWeight: 700, color: "#ffffff" },
  cabSub: { fontSize: 8.5, color: "#b9c6d8", marginTop: 2 },
  cuerpo: { paddingHorizontal: 36, paddingTop: 18 },
  eyebrow: { fontSize: 8, fontWeight: 800, color: C.brand, textTransform: "uppercase", letterSpacing: 0.6 },
  nombre: { fontSize: 20, fontWeight: 800, color: C.navy, marginTop: 3 },
  muted: { color: C.muted },
  kpis: { flexDirection: "row", gap: 8, marginTop: 12 },
  kpi: { flex: 1, borderRadius: 8, padding: 10, backgroundColor: C.soft },
  kpiHl: { backgroundColor: C.navy },
  kpiL: { fontSize: 8, fontWeight: 700, color: C.muted },
  kpiLHl: { color: "#b9c6d8" },
  kpiV: { fontSize: 18, fontWeight: 800, color: C.navy, marginTop: 3 },
  kpiVHl: { color: "#ffffff" },
  kpiD: { fontSize: 7.5, color: C.muted, marginTop: 2 },
  kpiDHl: { color: "#b9c6d8" },
  aviso: { marginTop: 10, padding: 8, borderRadius: 6, backgroundColor: C.bg, fontSize: 8.5, color: C.muted },
  h2: { fontSize: 12, fontWeight: 700, color: C.navy, marginTop: 18, marginBottom: 2 },
  lead: { fontSize: 8.5, color: C.muted, marginBottom: 6 },
  fila: { flexDirection: "row", alignItems: "center", paddingVertical: 4, borderBottomWidth: 0.5, borderBottomColor: C.line },
  colEtiqueta: { flex: 1.6, paddingRight: 6 },
  colBarra: { flex: 1, height: 7, backgroundColor: C.bg, borderRadius: 4 },
  relleno: { height: 7, backgroundColor: C.brand, borderRadius: 4 },
  colValor: { width: 46, textAlign: "right", fontWeight: 700 },
  colN: { width: 40, textAlign: "right", color: C.muted, fontSize: 8 },
  thFila: { flexDirection: "row", paddingVertical: 4, borderBottomWidth: 1, borderBottomColor: C.navy },
  th: { fontSize: 7.5, fontWeight: 700, color: C.muted, textTransform: "uppercase" },
  colPregunta: { flex: 1, paddingRight: 6 },
  colNum: { width: 52, textAlign: "right" },
  oculto: { color: C.muted, fontWeight: 600, fontSize: 8 },
  nota: { fontSize: 7.5, color: C.muted, marginTop: 4, lineHeight: 1.4 },
  pie: { position: "absolute", bottom: 18, left: 36, right: 36, flexDirection: "row", justifyContent: "space-between", fontSize: 7, color: C.muted, borderTopWidth: 0.5, borderTopColor: C.line, paddingTop: 6 },
});

function textoOculto(fila: { motivo?: string }) {
  return fila.motivo === "menos_de_5" ? t.oculto_menos5 : fila.motivo === "sin_datos" ? t.sin_datos : `${t.oculto_compl}*`;
}

function Media({ fila, estilo }: { fila?: Fila; estilo?: Style }) {
  if (!fila) return <Text style={estilo}>·</Text>;
  return fila.suprimido ? <Text style={[s.oculto, estilo ?? {}]}>{textoOculto(fila)}</Text> : <Text style={estilo}>{f.media(fila.media!)}</Text>;
}

export interface DatosInformePdf {
  profesor: { nombre: string; apellidos: string; departamento: string | null };
  informe: InformeProfesor;
  generado: Date;
}

export function InformeProfesorPdf({ profesor, informe, generado }: DatosInformePdf) {
  const g = informe.global;
  const etapas = Object.keys(informe.comparacion).filter((k) => k !== "colegio");
  const nombreEtapa = (e: string) => t.etapas[e as keyof typeof t.etapas] ?? e;
  const celdas = [...informe.celdas].sort((a, b) =>
    a.clave.asignatura.localeCompare(b.clave.asignatura, "es") || a.clave.grupo.localeCompare(b.clave.grupo, "es", { numeric: true }));
  const fecha = generado.toLocaleDateString("es-ES", { day: "numeric", month: "long", year: "numeric" });
  const hayComplementaria = celdas.some((c) => c.motivo === "complementaria");

  return (
    <Document title={`${t.prof_informe} · ${profesor.nombre} ${profesor.apellidos}`} author="Colegio Internacional de Sevilla – San Francisco de Paula" language="es">
      <Page size="A4" style={s.pagina}>
        <View style={s.cabecera} fixed>
          <Image src={logoBlanco} style={s.logo} />
          <View style={s.cabTexto}>
            <Text style={s.cabTitulo}>{t.brand_title}</Text>
            <Text style={s.cabSub}>{t.pdf_cab_sub}</Text>
          </View>
        </View>

        <View style={s.cuerpo}>
          <Text style={s.eyebrow}>{t.prof_informe}</Text>
          <Text style={s.nombre}>{profesor.nombre} {profesor.apellidos}</Text>
          {profesor.departamento && <Text style={s.muted}>{t.prof_departamento}: {profesor.departamento}</Text>}

          <View style={s.kpis}>
            <View style={[s.kpi, s.kpiHl]}>
              <Text style={[s.kpiL, s.kpiLHl]}>{t.prof_media_global}</Text>
              <Text style={[s.kpiV, s.kpiVHl]}>{g.suprimido ? t.prof_sin_visibles : `${f.media(g.media!)} / 6`}</Text>
              {!g.suprimido && <Text style={[s.kpiD, s.kpiDHl]}>{t.prof_global_d(g.combinaciones!, f.recuento(g.n_valoraciones!))}</Text>}
            </View>
            {etapas.map((e) => (
              <View key={e} style={s.kpi}>
                <Text style={s.kpiL}>{t.prof_media_etapa(nombreEtapa(e))}</Text>
                <Media fila={informe.comparacion[e]} estilo={s.kpiV} />
              </View>
            ))}
            {informe.comparacion.colegio && (
              <View style={s.kpi}>
                <Text style={s.kpiL}>{t.prof_media_colegio}</Text>
                <Media fila={informe.comparacion.colegio} estilo={s.kpiV} />
              </View>
            )}
          </View>
          {informe.combinaciones_excluidas > 0 && <Text style={s.aviso}>{t.prof_excluidas(informe.combinaciones_excluidas)}</Text>}

          <Text style={s.h2}>{t.prof_por_asignatura}</Text>
          <Text style={s.lead}>{t.prof_por_asignatura_lead}</Text>
          {celdas.map((c) => (
            <View key={`${c.clave.cuestionario}-${c.clave.grupo}-${c.clave.asignatura}`} style={s.fila} wrap={false}>
              <Text style={s.colEtiqueta}>{c.clave.asignatura} · {c.clave.grupo}</Text>
              <View style={s.colBarra}>
                {!c.suprimido && <View style={[s.relleno, { width: `${((c.media! - 1) / 5) * 100}%` }]} />}
              </View>
              <Media fila={c} estilo={s.colValor} />
              <Text style={s.colN}>{c.suprimido ? "" : `n ${f.recuento(c.n!)}`}</Text>
            </View>
          ))}

          <Text style={s.h2}>{t.prof_detalle}</Text>
          <Text style={s.lead}>{t.prof_detalle_lead}</Text>
          <View style={s.thFila} fixed={false}>
            <Text style={[s.th, s.colPregunta]}>{t.pregunta}</Text>
            <Text style={[s.th, s.colNum]}>{t.prof_col_profesor}</Text>
            {etapas.map((e) => <Text key={e} style={[s.th, s.colNum]}>{nombreEtapa(e)}</Text>)}
            {informe.comparacion.colegio && <Text style={[s.th, s.colNum]}>{t.prof_col_colegio}</Text>}
          </View>
          {informe.preguntas.map((p) => (
            <View key={p.codigo} style={s.fila} wrap={false}>
              <Text style={s.colPregunta}>{p.texto}</Text>
              <Text style={[s.colNum, { fontWeight: 700 }]}>
                {p.resultado.global.suprimido ? t.oculto_menos5 : f.media(p.resultado.global.media!)}
              </Text>
              {etapas.map((e) => <Media key={e} fila={p.resultado.comparacion[e]} estilo={s.colNum} />)}
              {informe.comparacion.colegio && <Media fila={p.resultado.comparacion.colegio} estilo={s.colNum} />}
            </View>
          ))}

          <Text style={[s.nota, { marginTop: 14 }]}>{t.pdf_nota_escala}</Text>
          <Text style={s.nota}>{t.pdf_nota_oculto}{hayComplementaria ? ` ${t.pdf_nota_asterisco}` : ""}</Text>
          <Text style={s.nota}>{t.aviso_cierre}</Text>
        </View>

        <View style={s.pie} fixed>
          <Text>{t.pdf_pie(fecha)}</Text>
          <Text render={({ pageNumber, totalPages }) => t.pdf_pagina(pageNumber, totalPages)} />
        </View>
      </Page>
    </Document>
  );
}
