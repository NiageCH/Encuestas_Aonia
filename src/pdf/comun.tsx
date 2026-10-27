// Piezas comunes de los PDF (§8): tipografía Raleway, colores de :root, cabecera con el logo
// del colegio, marca de agua y pie con quién lo descargó, cuándo, su código y la página.

import { Font, Image, StyleSheet, Text, View } from "@react-pdf/renderer";
import { AVISO_VALIDACION } from "../ajustes";
import { t } from "../i18n";
import logoBlanco from "../recursos/pdf/logo-blanco.png";
import r400 from "../recursos/pdf/Raleway-400.ttf";
import r600 from "../recursos/pdf/Raleway-600.ttf";
import r700 from "../recursos/pdf/Raleway-700.ttf";
import r800 from "../recursos/pdf/Raleway-800.ttf";
import { ESCALA_1_6, PALETA, aclarar, textoSobre } from "../paleta";
import type { SelloDescarga } from "../exportacion/modelo";

Font.register({
  family: "Raleway",
  fonts: [
    { src: r400, fontWeight: 400 }, { src: r600, fontWeight: 600 },
    { src: r700, fontWeight: 700 }, { src: r800, fontWeight: 800 },
  ],
});
Font.registerHyphenationCallback((palabra) => [palabra]);

// Copia literal de las variables de :root de la intranet (el PDF no lee CSS) y, para gráficos, indicadores y alertas,
// la paleta de src/paleta.ts (el mismo sitio del que la toma la web).
export const C = {
  navy: "#1a2c4a", brand: "#0063a3", sky: "#4495ce", muted: "#5b6573", line: "#dde3ea", soft: "#eaf0f6", bg: "#f2f4f7",
  ink: "#1a2c4a",
  grafico1: PALETA.grafico1, neutro: PALETA.neutro, neutroSuave: aclarar(PALETA.neutro, 10),
  escala: ESCALA_1_6,                                 // 1 a 6
  escalaTexto: ESCALA_1_6.map(textoSobre),
};

export const base = StyleSheet.create({
  pagina: { fontFamily: "Raleway", fontSize: 9.5, color: C.ink, paddingTop: 0, paddingBottom: 46, paddingHorizontal: 0 },
  cabecera: { backgroundColor: C.navy, paddingVertical: 14, paddingHorizontal: 36, flexDirection: "row", alignItems: "center", justifyContent: "space-between" },
  logo: { width: 120, height: 42 },
  cabTexto: { textAlign: "right" },
  cabTitulo: { fontSize: 11, fontWeight: 700, color: "#ffffff" },
  cabSub: { fontSize: 8.5, color: "#b9c6d8", marginTop: 2 },
  cuerpo: { paddingHorizontal: 36, paddingTop: 18 },
  validacion: { backgroundColor: C.neutroSuave, borderBottomWidth: 2, borderBottomColor: C.neutro, color: C.ink, fontSize: 8.5, fontWeight: 700, textAlign: "center", paddingVertical: 5, paddingHorizontal: 36 },
  eyebrow: { fontSize: 8, fontWeight: 800, color: C.brand, textTransform: "uppercase", letterSpacing: 0.6 },
  titulo: { fontSize: 20, fontWeight: 800, color: C.navy, marginTop: 3 },
  muted: { color: C.muted },
  h2: { fontSize: 12, fontWeight: 700, color: C.navy, marginTop: 18, marginBottom: 2 },
  lead: { fontSize: 8.5, color: C.muted, marginBottom: 6 },
  aviso: { marginTop: 10, padding: 8, borderRadius: 6, backgroundColor: C.neutroSuave, borderLeftWidth: 3, borderLeftColor: C.neutro, fontSize: 8.5, color: C.ink },
  nota: { fontSize: 7.5, color: C.muted, marginTop: 4, lineHeight: 1.4 },
  oculto: { color: C.muted, fontWeight: 600, fontSize: 8 },
  pie: { position: "absolute", bottom: 18, left: 36, right: 36, flexDirection: "row", justifyContent: "space-between", gap: 12, fontSize: 7, color: C.muted, borderTopWidth: 0.5, borderTopColor: C.line, paddingTop: 6 },
  // Marca de agua: detrás de todo (es lo primero de cada página), en diagonal y muy clara, para no tapar cifras ni gráficos.
  marca: { position: "absolute", top: 0, left: 0, right: 0, bottom: 0, alignItems: "center", justifyContent: "center" },
  marcaTexto: { width: 900, textAlign: "center", fontSize: 17, fontWeight: 700, color: "#000000", opacity: 0.1, letterSpacing: 0.5, transform: "rotate(-52deg)" },
});

/** «CONFIDENCIAL · Uso exclusivo del Colegio…», en todas las páginas. Va la primera en cada Page. */
export function MarcaAgua() {
  return <View style={base.marca} fixed><Text style={base.marcaTexto}>{t.desc_marca}</Text></View>;
}

/** 27/10/2026 a las 22:15 (hora de Madrid). */
export function fechaHoraDescarga(d: Date): string {
  const f = (o: Intl.DateTimeFormatOptions) => d.toLocaleString("es-ES", { timeZone: "Europe/Madrid", ...o });
  return t.desc_fecha_hora(f({ day: "2-digit", month: "2-digit", year: "numeric" }), f({ hour: "2-digit", minute: "2-digit" }));
}

export function Cabecera({ subtitulo }: { subtitulo: string }) {
  return (
    <>
      <View style={base.cabecera} fixed>
        <Image src={logoBlanco} style={base.logo} />
        <View style={base.cabTexto}>
          <Text style={base.cabTitulo}>{t.brand_title}</Text>
          <Text style={base.cabSub}>{subtitulo}</Text>
        </View>
      </View>
      {AVISO_VALIDACION && <Text style={base.validacion} fixed>{t.aviso_validacion}</Text>}
    </>
  );
}

export function Pie({ sello }: { sello: SelloDescarga }) {
  return (
    <View style={base.pie} fixed>
      <Text style={{ flex: 1 }}>{t.desc_pie(sello.nombre, fechaHoraDescarga(sello.fecha), sello.codigo)}</Text>
      <Text render={({ pageNumber, totalPages }) => t.pdf_pagina(pageNumber, totalPages)} />
    </View>
  );
}

export function textoOculto(fila: { motivo?: string }) {
  return fila.motivo === "menos_de_5" ? t.oculto_menos5 : fila.motivo === "sin_datos" ? t.sin_datos : `${t.oculto_compl}*`;
}
