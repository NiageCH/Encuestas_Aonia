// PDF de una vista (§7.6): la misma cabecera y las mismas tablas que el CSV, con el estilo de los
// informes del colegio (logo, franja de validación si está activa y pie con la página).

import { Document, Page, StyleSheet, Text, View } from "@react-pdf/renderer";
import { t } from "../i18n";
import { base, C, Cabecera, Pie } from "../pdf/comun";
import { cabecera, numeroCsv } from "./csv";
import type { Exportacion, Tabla, Valor } from "./modelo";

const s = StyleSheet.create({
  datos: { marginTop: 10, padding: 8, borderRadius: 6, backgroundColor: C.bg },
  dato: { flexDirection: "row", fontSize: 8, marginBottom: 1.5 },
  datoK: { width: 110, fontWeight: 700, color: C.muted },
  datoV: { flex: 1, color: C.ink, fontWeight: 400 },
  fila: { flexDirection: "row", alignItems: "center", paddingVertical: 3, borderBottomWidth: 0.5, borderBottomColor: C.line, fontSize: 8, fontWeight: 400 },
  cab: { flexDirection: "row", alignItems: "flex-end", paddingVertical: 3, borderBottomWidth: 1, borderBottomColor: C.navy, fontSize: 7.5, fontWeight: 700, color: C.navy },
  primera: { flex: 1, paddingRight: 6 },
  num: { paddingLeft: 4 },
  der: { textAlign: "right" },
  oculto: { color: C.muted, fontWeight: 600, fontSize: 7.5 },
});

/** Número como en pantalla: coma decimal y signo menos tipográfico. */
const numero = (x: number, dec: number) => numeroCsv(x, dec).replace("-", "−");

function Celda({ v, ancho, primera }: { v: Valor; ancho: number; primera: boolean }) {
  const estilo = primera ? s.primera : [{ width: ancho }, s.num, s.der];
  if ("num" in v) return <Text style={estilo}>{numero(v.num, v.dec)}</Text>;
  if ("oculto" in v) return <Text style={[...[estilo].flat(), s.oculto]}>{v.oculto}</Text>;
  return <Text style={estilo}>{v.texto}</Text>;
}

/** Ancho de una columna de cifras según su cabecera: «1» estrecha, «Valoraciones» ancha. */
const anchoColumna = (c: string) => (c.length <= 3 ? 24 : c.length <= 6 ? 40 : 60);

/** Si todas las cifras de la fila están ocultas por el mismo motivo, se dice una sola vez. */
function ocultaEntera(f: Valor[]): string | null {
  const resto = f.slice(1);
  const primero = resto[0];
  if (!primero || !("oculto" in primero)) return null;
  return resto.every((v) => "oculto" in v && v.oculto === primero.oculto) ? primero.oculto : null;
}

function TablaPdf({ tabla }: { tabla: Tabla }) {
  const anchos = tabla.columnas.map(anchoColumna);
  const sumaCifras = anchos.slice(1).reduce((a, b) => a + b, 0);
  return (
    <View>
      <View wrap={false} minPresenceAhead={40}>
        <Text style={base.h2}>{tabla.titulo}</Text>
        {tabla.filas.length > 0 && (
          <View style={s.cab}>
            {tabla.columnas.map((c, i) => <Text key={i} style={i === 0 ? s.primera : [{ width: anchos[i] }, s.num, s.der]}>{c}</Text>)}
          </View>
        )}
      </View>
      {tabla.filas.map((f, i) => {
        const oculta = f.length > 2 ? ocultaEntera(f) : null;
        return (
          <View key={i} style={s.fila} wrap={false}>
            <Celda v={f[0]} ancho={0} primera />
            {oculta ? <Text style={[{ width: sumaCifras }, s.der, s.oculto]}>{oculta}</Text>
              : f.slice(1).map((v, j) => <Celda key={j} v={v} ancho={anchos[j + 1]} primera={false} />)}
          </View>
        );
      })}
      {tabla.notas?.map((n, i) => <Text key={i} style={base.nota}>{n}</Text>)}
    </View>
  );
}

export function ExportacionPdf({ exportacion, generado, aviso }: { exportacion: Exportacion; generado: Date; aviso: boolean }) {
  return (
    <Document title={`${t.brand_title} · ${exportacion.titulo}`} author={t.colegio} language="es">
      <Page size="A4" style={base.pagina}>
        <Cabecera subtitulo={t.exp_pdf_sub} />
        {/* Aire bajo la cabecera también en las páginas siguientes */}
        <View fixed style={{ height: 8 }} />
        <View style={base.cuerpo}>
          <Text style={base.eyebrow}>{t.exp_pdf_eyebrow}</Text>
          <Text style={base.titulo}>{exportacion.titulo}</Text>
          <View style={s.datos}>
            {cabecera(exportacion, generado, aviso).map(([k, v]) => (
              <View key={k} style={s.dato}><Text style={s.datoK}>{k}</Text><Text style={s.datoV}>{v}</Text></View>
            ))}
          </View>
          {exportacion.tablas.map((x, i) => <TablaPdf key={i} tabla={x} />)}
          <View style={{ marginTop: 14 }}>
            {exportacion.notas.map((n, i) => <Text key={i} style={base.nota}>{n}</Text>)}
          </View>
        </View>
        <Pie generado={generado} />
      </Page>
    </Document>
  );
}
