// PDF de los informes de tutoría y de servicios (§7.12 y §7.13): las mismas tablas que en pantalla
// (src/data/tablasResumen.ts), con la cabecera, la marca de agua, el pie con el código de descarga y la versión.

import { Document, Page, StyleSheet, Text, View } from "@react-pdf/renderer";
import type { TablaResumen, ValorResumen } from "../data/tablasResumen";
import { textoNota } from "../etiquetas";
import * as f from "../formato";
import { t } from "../i18n";
import { base, C, Cabecera, MarcaAgua, Pie } from "./comun";
import type { SelloDescarga } from "../exportacion/modelo";

const s = StyleSheet.create({
  tabla: { marginTop: 6 },
  fila: { flexDirection: "row", borderBottomWidth: 0.5, borderBottomColor: C.line, paddingVertical: 4, alignItems: "flex-start" },
  cab: { borderBottomWidth: 1, borderBottomColor: C.navy },
  th: { fontSize: 7.5, fontWeight: 700, color: C.navy },
  pregunta: { flex: 1, paddingRight: 6, fontSize: 8.5 },
  secundaria: { paddingLeft: 8, color: C.muted },
  celda: { width: 74, textAlign: "right", paddingLeft: 4, fontSize: 8.5 },
  media: { fontWeight: 700 },
  n: { fontSize: 6.5, color: C.muted },
  oculto: { fontSize: 7.5, color: C.muted },
  referencia: { marginTop: 5, fontSize: 8, color: C.muted },
  notas: { marginTop: 5 },
  nota: { fontSize: 7, color: C.muted, marginTop: 1.5 },
});

function Celda({ v, fuerte }: { v: ValorResumen; fuerte: boolean }) {
  if ("nota" in v) return <Text style={[s.celda, s.oculto]}>{textoNota(v, true)}</Text>;
  return (
    <View style={s.celda}>
      <Text style={fuerte ? s.media : undefined}>{f.media(v.media)}</Text>
      <Text style={s.n}>{t.res_respuestas(f.recuento(v.n))}{v.menos_de_5 ? ` · ${t.marca_menos5}` : ""}</Text>
    </View>
  );
}

function Tabla({ tabla }: { tabla: TablaResumen }) {
  return (
    <View style={{ marginTop: 12 }}>
      <View wrap={false} minPresenceAhead={60}>
        <Text style={base.h2}>{tabla.titulo}</Text>
        <Text style={base.lead}>{tabla.lead}</Text>
        <View style={[s.fila, s.cab, s.tabla]}>
          <Text style={[s.pregunta, s.th]}>{t.pregunta}</Text>
          {tabla.columnas.map((c) => <Text key={c} style={[s.celda, s.th]}>{c}</Text>)}
        </View>
      </View>
      {tabla.filas.map((x) => (
        <View key={x.codigo} style={s.fila} wrap={false}>
          <Text style={[s.pregunta, x.secundaria ? s.secundaria : {}]}>{x.texto}</Text>
          {x.valores.map((v, i) => <Celda key={i} v={v} fuerte={i === 0} />)}
        </View>
      ))}
      {tabla.referencia && (
        <Text style={s.referencia}>
          {tabla.referencia.texto}: {"nota" in tabla.referencia.valor ? textoNota(tabla.referencia.valor, true)
            : `${f.media(tabla.referencia.valor.media)} (${t.res_respuestas(f.recuento(tabla.referencia.valor.n))})`}
        </Text>
      )}
      {tabla.notas.length > 0 && (
        <View style={s.notas}>{tabla.notas.map((n) => <Text key={n} style={s.nota}>{t.prof_notas[n]}</Text>)}</View>
      )}
    </View>
  );
}

export interface DatosResumenPdf {
  eyebrow: string;
  titulo: string;
  subtitulo: string;
  /** Aviso antes de las tablas (grupo sin respuestas). */
  aviso?: string;
  tablas: TablaResumen[];
  /** completa (Dirección y administración) o la del destinatario, con el mínimo de 5. */
  version: "completa" | "tutor" | "responsable";
  sello: SelloDescarga;
}

export function InformeResumenPdf({ eyebrow, titulo, subtitulo, aviso, tablas, version, sello }: DatosResumenPdf) {
  const conMinimo = version !== "completa";
  const corta = version === "tutor" ? t.version_tutor_corta : version === "responsable" ? t.version_responsable_corta : t.version_completa_corta;
  const larga = version === "tutor" ? t.version_tutor : version === "responsable" ? t.version_responsable
    : `${t.version_completa} · ${eyebrow === t.tut_informe ? t.pdf_version_completa_tutor : t.pdf_version_completa_responsable}`;
  const hayComplementaria = tablas.some((x) => x.notas.includes("complementaria"));
  return (
    <Document title={`${eyebrow} · ${titulo}`} author="Colegio Internacional de Sevilla, San Francisco de Paula" subject={t.desc_asunto} language="es">
      <Page size="A4" style={base.pagina}>
        <MarcaAgua />
        <Cabecera subtitulo={`${t.pdf_cab_curso} · ${eyebrow} · ${corta}`} />
        <View style={base.cuerpo}>
          <Text style={base.eyebrow}>{eyebrow}</Text>
          <Text style={base.titulo}>{titulo}</Text>
          <Text style={base.muted}>{subtitulo}</Text>
          <Text style={{ marginTop: 6, paddingVertical: 4, paddingHorizontal: 8, borderLeftWidth: 3, borderLeftColor: C.neutro,
                         backgroundColor: C.neutroSuave, fontSize: 8.5, fontWeight: 700, color: C.ink }}>{larga}</Text>
          {aviso && <Text style={[base.aviso, { marginTop: 12 }]}>{aviso}</Text>}
          {tablas.map((x) => <Tabla key={x.clave} tabla={x} />)}
          <Text style={[base.nota, { marginTop: 14 }]}>{t.res_nota_escala}</Text>
          <Text style={base.nota}>{conMinimo ? t.pdf_nota_oculto : t.leyenda_menos5}</Text>
          {hayComplementaria && <Text style={base.nota}>{t.pdf_nota_asterisco}</Text>}
          <Text style={base.nota}>{conMinimo ? t.aviso_cierre : t.aviso_cierre_direccion}</Text>
        </View>
        <Pie sello={sello} />
      </Page>
    </Document>
  );
}
