// Piezas comunes de los PDF (§8): tipografía Raleway, colores de :root, cabecera con el logo
// del colegio y pie con la página.

import { Font, Image, StyleSheet, Text, View } from "@react-pdf/renderer";
import { AVISO_VALIDACION } from "../ajustes";
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

// Copia literal de las variables de :root de la intranet (el PDF no lee CSS), y las mezclas
// con blanco de las clases en-n1..3 y en-p1 (color-mix calculado).
export const C = {
  navy: "#1a2c4a", brand: "#0063a3", sky: "#4495ce", muted: "#5b6573", line: "#dde3ea", soft: "#eaf0f6", bg: "#f2f4f7",
  ink: "#1a2c4a", warn: "#b26a00",
  n3: "#b26a00", n2: "#d1a666", n1: "#e8d2b3", p1: "#a2cae6", p2: "#0063a3", p3: "#1a2c4a",
};

export const base = StyleSheet.create({
  pagina: { fontFamily: "Raleway", fontSize: 9.5, color: C.ink, paddingTop: 0, paddingBottom: 46, paddingHorizontal: 0 },
  cabecera: { backgroundColor: C.navy, paddingVertical: 14, paddingHorizontal: 36, flexDirection: "row", alignItems: "center", justifyContent: "space-between" },
  logo: { width: 120, height: 42 },
  cabTexto: { textAlign: "right" },
  cabTitulo: { fontSize: 11, fontWeight: 700, color: "#ffffff" },
  cabSub: { fontSize: 8.5, color: "#b9c6d8", marginTop: 2 },
  cuerpo: { paddingHorizontal: 36, paddingTop: 18 },
  validacion: { backgroundColor: "#fff3d6", color: C.warn, fontSize: 8.5, fontWeight: 700, textAlign: "center", paddingVertical: 5, paddingHorizontal: 36 },
  eyebrow: { fontSize: 8, fontWeight: 800, color: C.brand, textTransform: "uppercase", letterSpacing: 0.6 },
  titulo: { fontSize: 20, fontWeight: 800, color: C.navy, marginTop: 3 },
  muted: { color: C.muted },
  h2: { fontSize: 12, fontWeight: 700, color: C.navy, marginTop: 18, marginBottom: 2 },
  lead: { fontSize: 8.5, color: C.muted, marginBottom: 6 },
  aviso: { marginTop: 10, padding: 8, borderRadius: 6, backgroundColor: C.bg, fontSize: 8.5, color: C.muted },
  nota: { fontSize: 7.5, color: C.muted, marginTop: 4, lineHeight: 1.4 },
  oculto: { color: C.muted, fontWeight: 600, fontSize: 8 },
  pie: { position: "absolute", bottom: 18, left: 36, right: 36, flexDirection: "row", justifyContent: "space-between", fontSize: 7, color: C.muted, borderTopWidth: 0.5, borderTopColor: C.line, paddingTop: 6 },
});

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

export function Pie({ generado }: { generado: Date }) {
  const fecha = generado.toLocaleDateString("es-ES", { day: "numeric", month: "long", year: "numeric" });
  return (
    <View style={base.pie} fixed>
      <Text>{t.pdf_pie(fecha)}</Text>
      <Text render={({ pageNumber, totalPages }) => t.pdf_pagina(pageNumber, totalPages)} />
    </View>
  );
}

export function textoOculto(fila: { motivo?: string }) {
  return fila.motivo === "menos_de_5" ? t.oculto_menos5 : fila.motivo === "sin_datos" ? t.sin_datos : `${t.oculto_compl}*`;
}
