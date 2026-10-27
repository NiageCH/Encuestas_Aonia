import { describe, expect, it, vi } from "vitest";

// El cliente de Supabase necesita el navegador; aquí solo hace falta el curso.
vi.mock("../data/cliente", () => ({ CURSO: "2025/26" }));

import type { Fila } from "../data/resultados";
import { t } from "../i18n";
import { aCsv, campoCsv, nombreArchivo, numeroCsv } from "./csv";
import { celdas, tablaDetalle, tablaDistribucion, txt, type Exportacion } from "./modelo";

const visible: Fila = { clave: {}, suprimido: false, n: 12, n_personas: 12, n_valoraciones: 70, media: 4.675, ns_nc: 0,
  distribucion: { "1": 1, "4": 5, "6": 6 }, promotores_pct: 41.6667, neutros_pct: 25, detractores_pct: 33.3333, nps: -8.3333 };
const menos5: Fila = { clave: {}, suprimido: true, motivo: "menos_de_5" };
const compl: Fila = { clave: {}, suprimido: true, motivo: "complementaria" };

const ejemplo: Exportacion = {
  vista: "familias", titulo: "Familias", filtros: [["Etapa", "PAI"]], archivo: ["Familias", "Etapa-PAI"],
  tablas: [{ titulo: "Satisfacción por bloque", columnas: ["Bloque", "Personas", "Valoraciones", "Media (de 1 a 6)"],
    filas: [[txt("Comunicación; tutoría"), ...celdas(visible, ["personas", "valoraciones", "media"])],
            [txt("Servicios"), ...celdas(menos5, ["personas", "valoraciones", "media"])],
            [txt("Instalaciones"), ...celdas(compl, ["personas", "valoraciones", "media"])]] }],
  notas: ["Nota con \"comillas\""],
};
const fecha = new Date(2026, 9, 22, 16, 5);
const lineas = (csv: string) => csv.replace(/^﻿/, "").split("\r\n");

describe("CSV para Excel en español", () => {
  it("empieza con BOM, separa con punto y coma y termina las líneas con CRLF", () => {
    const csv = aCsv(ejemplo, fecha, true);
    expect(csv.charCodeAt(0)).toBe(0xfeff);
    expect(csv).toContain("\r\n");
    expect(csv.replace(/\r\n/g, "")).not.toMatch(/\n/);
    expect(lineas(csv)[0]).toBe(`${t.exp_colegio};${t.colegio}`);
  });

  it("lleva la cabecera con colegio, curso, vista, filtros, fecha y aviso de validación", () => {
    const l = lineas(aCsv(ejemplo, fecha, true));
    expect(l.slice(0, 6)).toEqual([
      `${t.exp_colegio};${t.colegio}`, `${t.exp_curso};Curso 2025/26`, `${t.exp_vista};Familias`,
      `${t.exp_filtros};Etapa: PAI`, `${t.exp_fecha};22/10/2026 16:05`, `${t.exp_aviso};${t.aviso_validacion}`,
    ]);
  });

  it("sin la franja de validación, no hay aviso; sin filtros, lo dice", () => {
    const csv = aCsv({ ...ejemplo, filtros: [] }, fecha, false);
    expect(csv).not.toContain(t.aviso_validacion);
    expect(csv).toContain(`${t.exp_filtros};${t.exp_sin_filtros}`);
  });

  it("decimales con coma, signo menos ASCII, sin separador de miles", () => {
    expect(numeroCsv(4.675, 2)).toBe("4,68");
    expect(numeroCsv(-8.3333, 0)).toBe("-8");
    expect(numeroCsv(-0.2, 0)).toBe("0");
    expect(numeroCsv(132088, 0)).toBe("132088");
    expect(lineas(aCsv(ejemplo, fecha, true))).toContain('"Comunicación; tutoría";12;70;4,68');
  });

  it("las celdas ocultas dicen «menos de 5» u «oculto», nunca quedan en blanco", () => {
    const l = lineas(aCsv(ejemplo, fecha, true));
    expect(l).toContain("Servicios;menos de 5;menos de 5;menos de 5");
    expect(l).toContain("Instalaciones;oculto;oculto;oculto");
    for (const x of l.slice(7).filter((y) => y.includes(";"))) expect(x.split(";")).not.toContain("");
  });

  it("entrecomilla los textos con punto y coma o comillas", () => {
    expect(campoCsv('dice "hola"')).toBe('"dice ""hola"""');
    expect(campoCsv("a;b")).toBe('"a;b"');
    expect(campoCsv("normal")).toBe("normal");
  });

  it("el detalle por pregunta da 0 (no blanco) en las puntuaciones que nadie elige", () => {
    const tabla = tablaDetalle("Centro", [{ texto: "P1", fila: visible }], t.escala_acuerdo_fam);
    expect(tabla.filas[0].map((v) => ("num" in v ? v.num : null))).toEqual([null, 12, 4.675, 1, 0, 0, 5, 0, 6, 0]);
  });

  it("la distribución de una recomendación oculta no da ninguna cifra", () => {
    const tabla = tablaDistribucion(menos5, 1);
    expect(tabla.filas).toEqual([[txt(t.exp_todas), { oculto: t.oculto_menos5 }, { oculto: t.oculto_menos5 }]]);
  });
});

describe("nombre de archivo", () => {
  it("claro y sin acentos ni espacios", () => {
    expect(nombreArchivo(["Familias", "Etapa-PAI"], "csv")).toBe("Encuestas_2526_Familias_Etapa-PAI.csv");
    expect(nombreArchivo(["Panel general"], "pdf")).toBe("Encuestas_2526_Panel-general.pdf");
    expect(nombreArchivo(["Alumnos", "PAI asignaturas (Y6 a Y9)", "Grupo-Y7 A"], "csv"))
      .toBe("Encuestas_2526_Alumnos_PAI-asignaturas-Y6-a-Y9_Grupo-Y7-A.csv");
    expect(nombreArchivo(["Personal", "Primer año en el Colegio"], "csv")).toBe("Encuestas_2526_Personal_Primer-ano-en-el-Colegio.csv");
  });
});

describe("enunciados en el CSV", () => {
  it("copia el enunciado exactamente como está guardado, sin mayúscula inicial", () => {
    const tabla = tablaDetalle("Profesorado", [{ texto: "se comprenden bien las explicaciones", fila: visible }], ["a", "b", "c", "d", "e", "f"]);
    const csv = aCsv({ ...ejemplo, tablas: [tabla] }, fecha, false);
    expect(csv).toContain("\r\nse comprenden bien las explicaciones;");
    expect(csv).not.toContain("Se comprenden bien las explicaciones");
  });
});

describe("rangos sin partir", () => {
  it("la web y el PDF llevan espacios que no se parten; el CSV, espacios normales", () => {
    expect(t.exp_col_si).toBe("%\u00a0favorables (9\u00a0y\u00a010)");
    const csv = aCsv({ ...ejemplo, tablas: [{ titulo: t.exp_col_si, columnas: [t.exp_col_media], filas: [] }] }, fecha, false);
    expect(csv).toContain("% favorables (9 y 10)");
    expect(csv).not.toContain("\u00a0");
  });
});
