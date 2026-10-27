// PDF de una vista (§7.6): la misma cabecera y las mismas tablas que el CSV, con el estilo de los
// informes del colegio (logo, franja de validación si está activa y pie con la página).

import { Document, Page, StyleSheet, Text, View } from "@react-pdf/renderer";
import { t } from "../i18n";
import { base, C, Cabecera, MarcaAgua, Pie } from "../pdf/comun";
import { cabecera, numeroCsv } from "./csv";
import type { Exportacion, SelloDescarga, Tabla, Valor } from "./modelo";
import { mayusculaInicial } from "../formato";
import { sinCortes } from "../rangos";

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
  if ("enunciado" in v) return <Text style={estilo}>{mayusculaInicial(v.enunciado)}</Text>;
  return <Text style={estilo}>{sinCortes(v.texto)}</Text>;
}

// Anchos de columna (revisión de lenguaje): ninguna celda se parte palabra a palabra. Cada columna mide al menos su
// palabra más larga y, si cabe, su texto entero; la cabecera puede ir en dos líneas. Si no cabe todo, las columnas se
// estrechan hasta su palabra más larga, nunca menos, y la primera columna se queda con el resto.
const ANCHO_UTIL = 520;
const PRIMERA_MIN = 150;
const CAR = 4.7;   // ancho medio de un carácter de Raleway a 8 pt
const medida = (x: string) => x.length * CAR + 8;
const palabraMasLarga = (x: string) => Math.max(...x.split(/[ \t\n]+/).map(medida));
const textoCelda = (v: Valor) => sinCortes("num" in v ? numero(v.num, v.dec) : "oculto" in v ? v.oculto : "enunciado" in v ? v.enunciado : v.texto);

export function anchosColumnas(tabla: Tabla): number[] {
  const cols = tabla.columnas.map((c, j) => {
    if (j === 0) return { min: 0, ideal: 0 };
    const textos = tabla.filas.map((f) => f[j]).filter(Boolean).map(textoCelda);
    const min = Math.max(24, palabraMasLarga(sinCortes(c)) * 1.05, ...textos.map(palabraMasLarga));
    const ideal = Math.max(min, Math.min(medida(c) * 1.05 / 2 + 8, 90), ...textos.map((x) => Math.min(medida(x), 110)));
    return { min, ideal };
  });
  const resto = cols.slice(1);
  const disponible = ANCHO_UTIL - PRIMERA_MIN;
  const ideal = resto.reduce((a, c) => a + c.ideal, 0);
  if (ideal <= disponible) return [0, ...resto.map((c) => c.ideal)];
  const minimo = resto.reduce((a, c) => a + c.min, 0);
  const k = minimo >= disponible ? 0 : (disponible - minimo) / (ideal - minimo);
  return [0, ...resto.map((c) => c.min + (c.ideal - c.min) * k)];
}

/** Si todas las cifras de la fila están ocultas por el mismo motivo, se dice una sola vez. */
function ocultaEntera(f: Valor[]): string | null {
  const resto = f.slice(1);
  const primero = resto[0];
  if (!primero || !("oculto" in primero)) return null;
  return resto.every((v) => "oculto" in v && v.oculto === primero.oculto) ? primero.oculto : null;
}

function TablaPdf({ tabla }: { tabla: Tabla }) {
  const anchos = anchosColumnas(tabla);
  const sumaCifras = anchos.slice(1).reduce((a, b) => a + b, 0);
  return (
    <View>
      <View wrap={false} minPresenceAhead={40}>
        <Text style={base.h2}>{tabla.titulo}</Text>
        {tabla.filas.length > 0 && (
          <View style={s.cab}>
            {tabla.columnas.map((c, i) => <Text key={i} style={i === 0 ? s.primera : [{ width: anchos[i] }, s.num, s.der]}>{sinCortes(c)}</Text>)}
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

export function ExportacionPdf({ exportacion, sello, aviso }: { exportacion: Exportacion; sello: SelloDescarga; aviso: boolean }) {
  return (
    <Document title={`${t.brand_title} · ${exportacion.titulo}`} author={t.colegio} subject={t.desc_asunto} language="es">
      <Page size="A4" style={base.pagina}>
        <MarcaAgua />
        <Cabecera subtitulo={t.exp_pdf_sub} />
        {/* Aire bajo la cabecera también en las páginas siguientes */}
        <View fixed style={{ height: 8 }} />
        <View style={base.cuerpo}>
          <Text style={base.eyebrow}>{t.exp_pdf_eyebrow}</Text>
          <Text style={base.titulo}>{exportacion.titulo}</Text>
          <View style={s.datos}>
            {cabecera(exportacion, sello, aviso).map(([k, v]) => (
              <View key={k} style={s.dato}><Text style={s.datoK}>{k}</Text><Text style={s.datoV}>{v}</Text></View>
            ))}
          </View>
          {exportacion.tablas.map((x, i) => <TablaPdf key={i} tabla={x} />)}
          <View style={{ marginTop: 14 }}>
            {exportacion.notas.map((n, i) => <Text key={i} style={base.nota}>{n}</Text>)}
          </View>
        </View>
        <Pie sello={sello} />
      </Page>
    </Document>
  );
}
