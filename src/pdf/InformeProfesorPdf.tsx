// Informe PDF por profesor (§7.2), con el estilo de la intranet (§8): logo, colores y
// tipografía. Mismos datos y mismas reglas que la vista: viene de la RPC informe_profesor.

import { Document, Page, StyleSheet, Text, View } from "@react-pdf/renderer";
import type { Style } from "@react-pdf/types";
import type { CeldaProfesor, Fila, InformeProfesor } from "../data/resultados";
import { etiquetaClase, ordenarClases } from "../etiquetas";
import * as f from "../formato";
import { t } from "../i18n";
import { base, C, Cabecera, MarcaAgua, Pie, textoOculto } from "./comun";
import type { SelloDescarga } from "../exportacion/modelo";

const s = StyleSheet.create({
  kpis: { flexDirection: "row", gap: 8, marginTop: 12 },
  kpi: { flex: 1, borderRadius: 8, padding: 10, backgroundColor: C.soft },
  kpiHl: { backgroundColor: C.navy },
  kpiL: { fontSize: 8, fontWeight: 700, color: C.muted },
  kpiLHl: { color: "#b9c6d8" },
  kpiV: { fontSize: 18, fontWeight: 800, color: C.navy, marginTop: 3 },
  kpiVHl: { color: "#ffffff" },
  kpiD: { fontSize: 7.5, color: C.muted, marginTop: 2 },
  kpiDHl: { color: "#b9c6d8" },
  fila: { flexDirection: "row", alignItems: "center", paddingVertical: 4, borderBottomWidth: 0.5, borderBottomColor: C.line },
  colEtiqueta: { flex: 1.6, paddingRight: 6 },
  colBarra: { flex: 1, height: 7, backgroundColor: C.bg, borderRadius: 4 },
  relleno: { height: 7, backgroundColor: C.grafico1, borderRadius: 4 },
  colValor: { width: 46, textAlign: "right", fontWeight: 700 },
  colN: { width: 40, textAlign: "right", color: C.muted, fontSize: 8 },
  thFila: { flexDirection: "row", paddingVertical: 4, borderBottomWidth: 1, borderBottomColor: C.navy },
  th: { fontSize: 7.5, fontWeight: 700, color: C.muted, textTransform: "uppercase" },
  colPregunta: { flex: 1, paddingRight: 6 },
  colNum: { width: 66, textAlign: "right" },
});

function Media({ fila, estilo }: { fila?: Fila; estilo?: Style }) {
  if (!fila) return <Text style={estilo}>·</Text>;
  return fila.suprimido ? <Text style={[base.oculto, estilo ?? {}]}>{textoOculto(fila)}</Text> : <Text style={estilo}>{f.media(fila.media!)}</Text>;
}

function FilaClase({ c }: { c: CeldaProfesor }) {
  return (
    <View style={s.fila} wrap={false}>
      <Text style={s.colEtiqueta}>{etiquetaClase(c)}</Text>
      <View style={s.colBarra}>
        {!c.suprimido && <View style={[s.relleno, { width: `${((c.media! - 1) / 5) * 100}%` }]} />}
      </View>
      <Media fila={c} estilo={s.colValor} />
      <Text style={s.colN}>{c.suprimido ? "" : `n ${f.recuento(c.n!)}`}</Text>
    </View>
  );
}

export interface DatosInformePdf {
  profesor: { nombre: string; apellidos: string; departamento: string | null };
  informe: InformeProfesor;
  sello: SelloDescarga;
}

export function InformeProfesorPdf({ profesor, informe, sello }: DatosInformePdf) {
  const g = informe.global;
  const etapas = Object.keys(informe.comparacion).filter((k) => k !== "colegio");
  const nombreEtapa = (e: string) => t.etapas[e as keyof typeof t.etapas] ?? e;
  const celdas = ordenarClases(informe.celdas);
  const propias = celdas.filter((c) => c.tipo !== "compartida");
  const compartidas = celdas.filter((c) => c.tipo === "compartida");
  const hayComplementaria = celdas.some((c) => c.motivo === "complementaria");

  return (
    <Document title={`${t.prof_informe} · ${profesor.nombre} ${profesor.apellidos}`} author="Colegio Internacional de Sevilla, San Francisco de Paula" subject={t.desc_asunto} language="es">
      <Page size="A4" style={base.pagina}>
        <MarcaAgua />
        <Cabecera subtitulo={t.pdf_cab_sub} />

        <View style={base.cuerpo}>
          <Text style={base.eyebrow}>{t.prof_informe}</Text>
          <Text style={base.titulo}>{profesor.nombre} {profesor.apellidos}</Text>
          {profesor.departamento && <Text style={base.muted}>{t.prof_departamento}: {profesor.departamento}</Text>}

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
          {informe.combinaciones_excluidas > 0 && <Text style={base.aviso}>{t.prof_excluidas(informe.combinaciones_excluidas)}</Text>}

          <Text style={base.h2}>{t.prof_por_asignatura}</Text>
          <Text style={base.lead}>{t.prof_por_asignatura_lead}</Text>
          {propias.length === 0 && <Text style={base.muted}>{compartidas.length ? t.prof_sin_propias : t.sin_datos_seccion}</Text>}
          {propias.map((c) => <FilaClase key={`${c.clave.cuestionario}-${c.clave.grupo}-${c.clave.asignatura}`} c={c} />)}

          {compartidas.length > 0 && (
            <>
              <Text style={base.h2}>{t.prof_compartidas}</Text>
              <Text style={base.aviso}>{t.prof_compartidas_nota}</Text>
              {compartidas.map((c) => <FilaClase key={`${c.clave.cuestionario}-${c.clave.grupo}-${c.clave.asignatura}`} c={c} />)}
            </>
          )}

          <Text style={base.h2}>{t.prof_detalle}</Text>
          <Text style={base.lead}>{t.prof_detalle_lead}</Text>
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

          <Text style={[base.nota, { marginTop: 14 }]}>{t.pdf_nota_escala}</Text>
          <Text style={base.nota}>{t.pdf_nota_oculto}</Text>
          {hayComplementaria && <Text style={base.nota}>{t.pdf_nota_asterisco}</Text>}
          <Text style={base.nota}>{t.aviso_cierre}</Text>
        </View>

        <Pie sello={sello} />
      </Page>
    </Document>
  );
}
