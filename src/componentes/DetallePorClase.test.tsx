import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { CeldaProfesor, InformeProfesor } from "../data/resultados";
import { DetallePorClase } from "./DetallePorClase";

const clave = (grupo: string) => ({ cuestionario: "X", grupo, asignatura: "Matemáticas" });
const celda = (grupo: string, x: Partial<CeldaProfesor>): CeldaProfesor =>
  ({ clave: clave(grupo), etapa: "pai", tipo: "propia", docentes_clase: 1, suprimido: false, ...x }) as CeldaProfesor;
const pregunta = (codigo: string, celdas: CeldaProfesor[]) =>
  ({ codigo, texto: `Pregunta ${codigo}`, resultado: { celdas } }) as unknown as InformeProfesor["preguntas"][number];

describe("detalle por clase (versión docente)", () => {
  const html = renderToStaticMarkup(
    <DetallePorClase
      celdas={[celda("Y7 B", { n: 8, media: 4.25 })]}
      preguntas={[
        pregunta("a", [celda("Y7 B", { suprimido: true, motivo: "menos_de_5" })]),
        pregunta("b", [celda("Y7 B", { suprimido: true, motivo: "complementaria" })]),
        pregunta("c", [celda("Y7 B", { n: 7, media: 3.5 })]),
      ]}
    />,
  );

  it("enseña cada pregunta de la clase", () => {
    expect(html).toContain("Pregunta a");
    expect(html).toContain("Pregunta c");
  });
  it("lo de menos de 5 sale como «menos de 5», sin cifra; lo de la complementaria, «oculto»", () => {
    expect(html).toMatch(/Pregunta a<\/td><td[^>]*><span class="en-oculto">menos.de.5<\/span><\/td><td[^>]*><\/td>/);
    expect(html).toMatch(/Pregunta b<\/td><td[^>]*><span class="en-oculto">oculto<\/span><\/td><td[^>]*><\/td>/);
    expect(html.match(/<tr>/g)?.length).toBe(4);
    expect(html).toContain("<strong>3,50</strong>");
    expect(html).not.toMatch(/Pregunta a<\/td><td[^>]*><strong>/);
  });
  it("debajo de la tabla, la nota de cada texto que sale en lugar de una cifra", () => {
    expect(html).toMatch(/«menos.de.5»: el resultado tiene menos.de.5 respuestas/);
    expect(html).toContain("«oculto»: se oculta para que no se pueda deducir otro resultado por resta");
    expect(html).not.toContain("·</td>");
  });
  it("sin la marca «menos de 5» de la versión completa", () => {
    expect(html).not.toContain("en-menos5");
  });
});

describe("clase oculta", () => {
  const html = renderToStaticMarkup(
    <DetallePorClase celdas={[celda("Y7 C", { suprimido: true, motivo: "menos_de_5" })]}
      preguntas={[pregunta("a", [celda("Y7 C", { suprimido: true, motivo: "menos_de_5" })])]} />,
  );
  it("una sola línea, sin la tabla de preguntas", () => {
    expect(html).toContain("No se muestra ninguna pregunta de esta clase");
    expect(html).not.toContain("<table");
  });
});
