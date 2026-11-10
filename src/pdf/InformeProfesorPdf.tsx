// Informe PDF por profesor (§7.2), con el estilo de la intranet (§8): logo, colores y
// tipografía. Mismos datos y mismas reglas que la vista: viene de la RPC informe_profesor.

import { Document, Page, StyleSheet, Text, View } from "@react-pdf/renderer";
import type { Style } from "@react-pdf/types";
import type { CeldaProfesor, Fila, InformeProfesor } from "../data/resultados";
import { deLaClase, etapasDelInforme, tablaProfesor, type ValorTabla } from "../data/tablaProfesor";
import { columnaProfesor, etiquetaClase, ordenarClases, textoNota } from "../etiquetas";
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
  colN: { width: 74, textAlign: "right", color: C.muted, fontSize: 8 },
  thFila: { flexDirection: "row", paddingVertical: 4, borderBottomWidth: 1, borderBottomColor: C.navy },
  thGrupos: { flexDirection: "row", marginTop: 4 },
  thGrupo: { textAlign: "center", color: C.navy, borderBottomWidth: 0.5, borderBottomColor: C.line, paddingBottom: 2, marginLeft: 6 },
  th: { fontSize: 7.5, fontWeight: 700, color: C.muted, textTransform: "uppercase" },
  colPregunta: { flex: 1, paddingRight: 6 },
  colNum: { width: 66, textAlign: "right" },
  version: { marginTop: 6, paddingVertical: 4, paddingHorizontal: 8, borderLeftWidth: 3, borderLeftColor: C.neutro, backgroundColor: C.neutroSuave,
             fontSize: 8.5, fontWeight: 700, color: C.ink },
  marca: { fontSize: 6.5, fontWeight: 700, color: C.ink },
  claseTit: { fontSize: 9.5, fontWeight: 700, color: C.navy, marginTop: 10, marginBottom: 2 },
});

/** «menos de 5» junto a una cifra (versión completa). */
function Marca({ fila }: { fila?: { menos_de_5?: boolean | number } }) {
  return fila?.menos_de_5 ? <Text style={s.marca}>{` ${t.marca_menos5}`}</Text> : null;
}

function Media({ fila, estilo }: { fila?: Fila; estilo?: Style }) {
  if (!fila) return <Text style={[base.oculto, estilo ?? {}]}>{t.sin_datos}</Text>;
  return fila.suprimido ? <Text style={[base.oculto, estilo ?? {}]}>{textoOculto(fila)}</Text> : <Text style={estilo}>{f.media(fila.media!)}</Text>;
}

/** Una celda del detalle por pregunta: la cifra o, si no la lleva, el texto de su nota. */
function ValorPdf({ v, estilo, estrecha }: { v: ValorTabla; estilo: Style[]; estrecha: boolean }) {
  if ("nota" in v) return <Text style={[base.oculto, ...estilo, estrecha ? { fontSize: 6.5, paddingLeft: 3 } : {}]}>{textoNota(v, true)}</Text>;
  return <Text style={estilo}>{f.media(v.media)}<Marca fila={v} /></Text>;
}

function FilaClase({ c }: { c: CeldaProfesor }) {
  return (
    <View style={s.fila} wrap={false}>
      <Text style={s.colEtiqueta}>{etiquetaClase(c)}</Text>
      <View style={s.colBarra}>
        {!c.suprimido && <View style={[s.relleno, { width: `${((c.media! - 1) / 5) * 100}%` }]} />}
      </View>
      <Media fila={c} estilo={s.colValor} />
      <Text style={s.colN}>{c.suprimido ? "" : `n ${f.recuento(c.n!)}`}<Marca fila={c} /></Text>
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
  const completa = informe.version === "completa";
  const etapas = etapasDelInforme(informe);
  const tabla = tablaProfesor(informe);
  const cols = tabla.columnas.map((c) => columnaProfesor(c, tabla, completa && !!g.menos_de_5));
  const estrecha = cols.length > 3;
  const colN: Style = { width: estrecha ? 56 : 66, textAlign: "right" };
  const grupos: { texto?: string; ancho: number }[] = [];
  for (const c of cols) {
    const ultimo = grupos[grupos.length - 1];
    if (c.grupo && ultimo?.texto === c.grupo) ultimo.ancho++;
    else grupos.push({ texto: c.grupo, ancho: 1 });
  }
  const nombreEtapa = (e: string) => t.etapas[e as keyof typeof t.etapas] ?? e;
  const celdas = ordenarClases(informe.celdas);
  const propias = celdas.filter((c) => c.tipo !== "compartida");
  const compartidas = celdas.filter((c) => c.tipo === "compartida");
  const hayComplementaria = celdas.some((c) => c.motivo === "complementaria")
    || informe.preguntas.some((p) => p.resultado.celdas.some((c) => c.motivo === "complementaria"));
  const version = completa ? t.version_completa : t.version_docente;

  return (
    <Document title={`${t.prof_informe} · ${profesor.nombre} ${profesor.apellidos}`} author="Colegio Internacional de Sevilla, San Francisco de Paula" subject={t.desc_asunto} language="es">
      <Page size="A4" style={base.pagina}>
        <MarcaAgua />
        <Cabecera subtitulo={`${t.pdf_cab_sub} · ${completa ? t.version_completa_corta : t.version_docente_corta}`} />

        <View style={base.cuerpo}>
          <Text style={base.eyebrow}>{t.prof_informe}</Text>
          <Text style={base.titulo}>{profesor.nombre} {profesor.apellidos}</Text>
          {profesor.departamento && <Text style={base.muted}>{t.prof_departamento}: {profesor.departamento}</Text>}
          <Text style={s.version}>{version}{completa ? ` · ${t.pdf_version_completa_nota}` : ""}</Text>

          <View style={s.kpis}>
            <View style={[s.kpi, s.kpiHl]}>
              <Text style={[s.kpiL, s.kpiLHl]}>{t.prof_media_global}</Text>
              <Text style={[s.kpiV, s.kpiVHl]}>{g.suprimido ? t.prof_sin_visibles : `${f.media(g.media!)} / 6`}</Text>
              {!g.suprimido && <Text style={[s.kpiD, s.kpiDHl]}>{t.prof_global_d(g.combinaciones!, f.recuento(g.n_valoraciones!))}</Text>}
              {!g.suprimido && g.menos_de_5 ? <Text style={[s.kpiD, s.kpiDHl]}>{t.prof_global_menos5(g.menos_de_5)}</Text> : null}
              {informe.global_docente && g.menos_de_5 ? <Text style={[s.kpiD, s.kpiDHl]}>
                {t.prof_global_docente(informe.global_docente.suprimido ? t.prof_sin_visibles : f.media(informe.global_docente.media!))}</Text> : null}
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
          {tabla.porPares && <Text style={base.lead}>{t.prof_detalle_lead_pares}</Text>}
          <View wrap={false} minPresenceAhead={60}>
            {tabla.porPares && (
              <View style={s.thGrupos}>
                <Text style={s.colPregunta}> </Text>
                {grupos.map((x, i) => <Text key={i} style={[s.th, s.thGrupo, { width: (colN.width as number) * x.ancho - 6 }]}>{x.texto ?? ""}</Text>)}
              </View>
            )}
            <View style={s.thFila}>
              <Text style={[s.th, s.colPregunta]}>{t.pregunta}</Text>
              {cols.map((c, i) => <Text key={i} style={[s.th, colN, { paddingLeft: 5 }, estrecha ? { fontSize: 6.5 } : {}]}>{c.titulo}</Text>)}
            </View>
          </View>
          {tabla.filas.map((fila) => (
            <View key={fila.codigo} style={s.fila} wrap={false}>
              <Text style={s.colPregunta}>{fila.texto}</Text>
              {fila.valores.map((v, i) => <ValorPdf key={i} v={v} estrecha={estrecha} estilo={i === 0 ? [colN, { fontWeight: 700 }] : [colN]} />)}
            </View>
          ))}
          {tabla.notas.map((n) => <Text key={n} style={base.nota}>{n === "complementaria" ? t.pdf_nota_asterisco : t.prof_notas[n]}</Text>)}

          {celdas.length > 0 && (
            <>
              <Text style={base.h2} break>{t.prof_por_clase}</Text>
              <Text style={base.lead}>{t.prof_por_clase_lead_pdf}</Text>
              {celdas.map((c) => (
                <View key={`${c.clave.cuestionario}-${c.clave.grupo}-${c.clave.asignatura}`}>
                  <View wrap={false}>
                    <Text style={s.claseTit}>
                      {etiquetaClase(c)}{c.tipo === "compartida" ? ` · ${t.prof_compartida_corto}` : ""}
                      {" · "}{c.suprimido ? textoOculto(c) : `${f.media(c.media!)} · n ${f.recuento(c.n!)}`}<Marca fila={c} />
                    </Text>
                    {c.suprimido ? <Text style={base.muted}>{t.prof_clase_oculta}</Text> : (
                      <View style={s.thFila}>
                        <Text style={[s.th, s.colPregunta]}>{t.pregunta}</Text>
                        <Text style={[s.th, s.colNum]}>{t.media}</Text>
                        <Text style={[s.th, s.colNum]}>n</Text>
                      </View>
                    )}
                  </View>
                  {!c.suprimido && deLaClase(informe.preguntas, c).map(({ codigo, texto, x }) => (
                    <View key={codigo} style={s.fila} wrap={false}>
                      <Text style={s.colPregunta}>{texto}</Text>
                      <Media fila={x} estilo={{ ...s.colNum, fontWeight: 700 }} />
                      <Text style={[s.colNum, { color: C.muted }]}>{!x.suprimido ? f.recuento(x.n!) : ""}<Marca fila={x} /></Text>
                    </View>
                  ))}
                </View>
              ))}
            </>
          )}

          <Text style={[base.nota, { marginTop: 14 }]}>{t.pdf_nota_escala}</Text>
          {completa ? <Text style={base.nota}>{t.leyenda_menos5}</Text> : <Text style={base.nota}>{t.pdf_nota_oculto}</Text>}
          {hayComplementaria && <Text style={base.nota}>{t.pdf_nota_asterisco}</Text>}
          <Text style={base.nota}>{completa ? t.aviso_cierre_direccion : t.aviso_cierre}</Text>
        </View>

        <Pie sello={sello} />
      </Page>
    </Document>
  );
}
