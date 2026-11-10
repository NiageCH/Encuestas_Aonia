import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { TablaPreguntasProfesor } from "../componentes/TablaPreguntasProfesor";
import type { CeldaProfesor, Fila, InformeProfesor, ResultadoProfesor } from "./resultados";
import { mediaDocente, tablaProfesor } from "./tablaProfesor";

const celda = (grupo: string, etapa: string, x: Partial<CeldaProfesor>): CeldaProfesor =>
  ({ clave: { cuestionario: "X", grupo, asignatura: "A" }, etapa, tipo: "propia", docentes_clase: 1, suprimido: false, ...x }) as CeldaProfesor;
const ref = (media: number): Fila => ({ clave: {}, suprimido: false, media });
const resultado = (celdas: CeldaProfesor[], comparacion: Record<string, Fila>): ResultadoProfesor => {
  const vis = celdas.filter((c) => c.tipo !== "compartida" && !c.suprimido);
  const n = vis.reduce((a, c) => a + c.n_valoraciones!, 0);
  return {
    docente: { id: 1, nombre: "", apellidos: "" }, celdas, combinaciones_excluidas: 0, compartidas: 0, comparacion,
    global: n ? { suprimido: false, combinaciones: vis.length, n_valoraciones: n, media: vis.reduce((a, c) => a + c.media! * c.n_valoraciones!, 0) / n }
      : { suprimido: true, motivo: "sin_combinaciones_visibles" },
  };
};

// Como el caso de Mark (versión docente), con cifras inventadas: tres clases propias de PAI, una oculta, y una
// compartida visible en Bachillerato.
const pai = [
  celda("Y7 A", "pai", { n: 20, n_valoraciones: 20, media: 5.5 }),
  celda("Y7 B", "pai", { n: 10, n_valoraciones: 10, media: 4 }),
  celda("Y7 C", "pai", { n: 10, n_valoraciones: 10, media: 6 }),
  celda("Y7 D", "pai", { suprimido: true, motivo: "menos_de_5" }),
];
const bach = [celda("Y11 A", "bachillerato", { tipo: "compartida", docentes_clase: 3, n: 12, n_valoraciones: 12, media: 5 })];
const claridad = resultado([...pai, ...bach], { pai: ref(4.2), bachillerato: ref(4.8) });
const informe = (preguntas: ResultadoProfesor[], version: "docente" | "completa" = "docente"): InformeProfesor => ({
  ...resultado([...pai, ...bach], { pai: ref(4.1), bachillerato: ref(4.9), colegio: ref(4.3) }),
  preguntas: preguntas.map((r, i) => ({ codigo: `p${i}`, texto: `Pregunta ${i}`, resultado: r })), version,
});

describe("tabla del detalle por pregunta", () => {
  const tabla = tablaProfesor(informe([claridad]));
  it("con dos etapas, por pares: este profesor/a y todo el profesorado en cada una, y el Colegio", () => {
    expect(tabla.porPares).toBe(true);
    expect(tabla.columnas.map((c) => c.tipo + ("etapa" in c ? `:${c.etapa}` : ""))).toEqual(
      ["docente", "docente_etapa:pai", "etapa:pai", "docente_etapa:bachillerato", "etapa:bachillerato", "colegio"]);
  });
  it("la media del docente es la de sus clases visibles (5,25), y la de PAI coincide, porque son todas de PAI", () => {
    const [docente, enPai, todosPai, enBach, todosBach, colegio] = tabla.filas[0].valores;
    expect(docente).toMatchObject({ media: 5.25 });
    expect("media" in enPai && enPai.media).toBeCloseTo(5.25, 10);
    expect(todosPai).toMatchObject({ media: 4.2 });
    expect(enBach).toEqual({ nota: "sin_propias" });
    expect(todosBach).toMatchObject({ media: 4.8 });
    expect(colegio).toEqual({ nota: "no_se_muestra" });
    expect(tabla.notas).toEqual(["sin_propias", "no_se_muestra"]);
  });
  it("en la versión completa, sin el Colegio no hay «no se muestra»", () => {
    expect(tablaProfesor(informe([claridad], "completa")).filas[0].valores[5]).toEqual({ nota: "sin_datos" });
  });
  it("la pregunta que no está en el cuestionario de una etapa", () => {
    const soloPai = resultado(pai, { pai: ref(4), colegio: ref(4) });
    const v = tablaProfesor(informe([soloPai])).filas[0].valores;
    expect(v[3]).toEqual({ nota: "no_se_pregunta" });
    expect(v[4]).toEqual({ nota: "no_se_pregunta" });
  });
  it("con clases propias pero todas ocultas: «sin datos visibles», también en su media", () => {
    const ocultas = resultado([celda("Y7 D", "pai", { suprimido: true, motivo: "menos_de_5" })], { pai: ref(4) });
    const v = tablaProfesor(informe([ocultas])).filas[0].valores;
    expect(v[0]).toEqual({ nota: "sin_visibles" });
    expect(v[1]).toEqual({ nota: "sin_visibles" });
  });
  it("la media por etapa pondera por valoraciones y deja fuera las compartidas", () => {
    expect(mediaDocente([celda("a", "pai", { n_valoraciones: 10, media: 6 }), celda("b", "pai", { n_valoraciones: 30, media: 2 }),
      celda("c", "pai", { tipo: "compartida", n_valoraciones: 100, media: 1 })])).toEqual({ media: 3 });
  });
  it("con una sola etapa, sin pares: «Media de PAI (todo el profesorado)»", () => {
    const uno = { ...informe([resultado(pai, { pai: ref(4.5) })]), comparacion: { pai: ref(4.1) } };
    const t1 = tablaProfesor(uno);
    expect(t1.porPares).toBe(false);
    expect(t1.columnas.map((c) => c.tipo)).toEqual(["docente", "etapa"]);
  });
});

describe("tabla en pantalla", () => {
  const html = renderToStaticMarkup(<TablaPreguntasProfesor informe={informe([claridad])} />);
  it("encabezados claros: este profesor/a y todo el profesorado, con la etapa encima", () => {
    expect(html).toContain("Este profesor/a (sus clases)");
    expect(html).toMatch(/colSpan="2"[^>]*>PAI</);
    expect(html).toContain("Todo el profesorado");
    expect(html).toContain("Media del Colegio (todo el profesorado)");
    expect(html).toContain('data-etiqueta="PAI, este profesor/a"');
  });
  it("una nota en lugar de «·», explicada debajo", () => {
    expect(html).not.toContain("·");
    expect(html).toContain(">no se muestra<");
    expect(html).toContain(">sin clases propias<");
    expect(html).toContain("con la media del Colegio se podría deducir");
    expect(html).toContain("5,25");
  });
});
