// Tablas de los informes de tutoría y de servicios. Cifras INVENTADAS.
import { describe, expect, it } from "vitest";
import type { Fila } from "./resultados";
import { tablasServicio, tablasTutoria, valorResumen } from "./tablasResumen";
import type { InformeServicio, InformeTutoria } from "./tutoriaServicios";

const visible = (media: number, n: number, extra: Partial<Fila> = {}): Fila => ({ clave: {}, suprimido: false, media, n, n_valoraciones: n, ...extra });
const oculta = (motivo: Fila["motivo"]): Fila => ({ clave: {}, suprimido: true, motivo });
const etapa = (e: string, f: Fila): Fila => ({ ...f, clave: { etapa: e } });

describe("valorResumen", () => {
  it("cifra y número de valoraciones, o la nota de por qué no hay cifra", () => {
    expect(valorResumen(visible(4.5, 12))).toEqual({ media: 4.5, n: 12 });
    expect(valorResumen(visible(4.5, 3, { menos_de_5: true }))).toEqual({ media: 4.5, n: 3, menos_de_5: true });
    expect(valorResumen(oculta("menos_de_5"))).toEqual({ nota: "menos_de_5" });
    expect(valorResumen(oculta("complementaria"))).toEqual({ nota: "complementaria" });
    expect(valorResumen(oculta("sin_datos"))).toEqual({ nota: "sin_datos" });
    expect(valorResumen(undefined)).toEqual({ nota: "no_se_pregunta" });
  });
});

const tutoria: InformeTutoria = {
  grupo: { id: 1, nombre: "Y7 B", etapa: "pai", cuestionario: "PAI_T" },
  tutor: { id: 9, nombre: "Ana", apellidos: "Ejemplo" },
  preguntas: [
    { codigo: "q1", texto: "El tutor atiende", grupo: visible(5.25, 20), etapa: visible(4.75, 300) },
    { codigo: "q2", texto: "El tutor ayuda", grupo: oculta("menos_de_5"), etapa: visible(4.5, 290) },
  ],
  colegio: [
    { codigo: "f1", texto: "Labor tutorial", colectivo: "familias", total: visible(4.8, 60) },
    { codigo: "p1", texto: "Labor tutorial", colectivo: "personal", total: visible(5.1, 40) },
  ],
  version: "tutor",
};

describe("tablasTutoria", () => {
  it("el grupo frente a toda su etapa, y la labor tutorial del Colegio aparte, como referencia", () => {
    const [grupo, colegio] = tablasTutoria(tutoria);
    expect(grupo.columnas).toEqual(["Este grupo (Y7 B)", "Todo el alumnado de PAI (todo el profesorado tutor)"]);
    expect(grupo.filas.map((f) => f.valores)).toEqual([
      [{ media: 5.25, n: 20 }, { media: 4.75, n: 300 }],
      [{ nota: "menos_de_5" }, { media: 4.5, n: 290 }],
    ]);
    expect(grupo.notas).toEqual(["menos_de_5"]);
    expect(colegio.columnas).toEqual(["Todo el Colegio"]);
    expect(colegio.filas.map((f) => f.texto)).toEqual(["Familias: Labor tutorial", "Personal: Labor tutorial"]);
    expect(colegio.notas).toEqual([]);
  });
  it("un grupo sin respuestas solo lleva la referencia del Colegio", () => {
    const tablas = tablasTutoria({ ...tutoria, preguntas: [] });
    expect(tablas.map((x) => x.clave)).toEqual(["colegio"]);
  });
});

const servicio: InformeServicio = {
  servicio: { id: 3, codigo: "biblioteca", nombre: "Biblioteca" },
  responsable: null,
  colectivos: [
    {
      colectivo: "alumnos",
      preguntas: [
        { codigo: "a1", texto: "Biblioteca", principal: true, total: visible(4.2, 200),
          etapas: [etapa("primaria", visible(4.9, 80)), etapa("pai", visible(4.0, 100)), etapa("bachillerato", oculta("complementaria"))] },
        { codigo: "a2", texto: "Me atienden bien", principal: false, total: visible(4.6, 90), etapas: [etapa("pai", visible(4.6, 90))] },
      ],
      servicios: visible(4.4, 2500),
    },
    {
      colectivo: "personal",
      preguntas: [{ codigo: "p1", texto: "Apoyo al aprendizaje", principal: false, total: oculta("menos_de_5"), etapas: [] }],
      servicios: null,
    },
  ],
  version: "responsable",
};

describe("tablasServicio", () => {
  it("una tabla por colectivo, con el total y las etapas en las que se pregunta", () => {
    const [alumnos, personal] = tablasServicio(servicio);
    expect(alumnos.columnas).toEqual(["Todo el alumnado", "Primaria", "PAI", "Bachillerato"]);
    expect(alumnos.filas[0].texto).toBe("Valoración del servicio («Biblioteca»)");
    expect(alumnos.filas[1]).toMatchObject({ texto: "Me atienden bien", secundaria: true });
    // La pregunta propia solo se hace en PAI: en las demás etapas, «no se pregunta», no un hueco.
    expect(alumnos.filas[1].valores).toEqual([{ media: 4.6, n: 90 }, { nota: "no_se_pregunta" }, { media: 4.6, n: 90 }, { nota: "no_se_pregunta" }]);
    expect(alumnos.filas[0].valores[3]).toEqual({ nota: "complementaria" });
    expect(alumnos.notas).toEqual(["complementaria", "no_se_pregunta"]);
    expect(alumnos.referencia).toEqual({ texto: "Media de todos los servicios según el alumnado (referencia)", valor: { media: 4.4, n: 2500 } });
    expect(personal.columnas).toEqual(["Todo el personal"]);
    expect(personal.referencia).toBeUndefined();
    expect(personal.notas).toEqual(["menos_de_5"]);
  });
});
