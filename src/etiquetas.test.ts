import { describe, expect, it } from "vitest";
import { textoParteOculta } from "./etiquetas";

describe("mensaje de una etapa o un grupo oculto", () => {
  it("familias con menos de 5: curso y etapa, sin la cifra exacta", () => {
    const x = textoParteOculta("menos_de_5", "2025/26", "familias", "Bachillerato");
    expect(x).toBe("En 2025/26 respondieron menos de 5 familias de Bachillerato. Con menos de 5 no se muestran resultados, para proteger el anonimato.");
    expect(x).not.toMatch(/respondieron [0-4] /);
  });
  it("por supresión complementaria se mantiene el texto de la resta", () => {
    expect(textoParteOculta("complementaria", "2025/26", "familias", "PAI")).toContain("deducir por resta");
    expect(textoParteOculta("complementaria", "2025/26", "alumnos", "Y9 D")).toContain("deducir por resta los de otros grupos");
  });
  it("alumnos con menos de 5 en un grupo", () => {
    expect(textoParteOculta("menos_de_5", "2025/26", "alumnos", "Y7 C")).toBe(
      "En 2025/26 hubo menos de 5 respuestas del alumnado de Y7 C. Con menos de 5 no se muestran resultados, para proteger el anonimato.");
  });
});

import { mayusculaInicial, textosConMayuscula } from "./formato";

describe("mayúscula inicial de las preguntas", () => {
  it("pone la primera letra en mayúscula sin tocar el resto", () => {
    expect(mayusculaInicial("se comprenden bien las explicaciones del Profesor")).toBe("Se comprenden bien las explicaciones del Profesor");
    expect(mayusculaInicial("¿te gusta?")).toBe("¿Te gusta?");
    expect(mayusculaInicial("«mi» tutor")).toBe("«Mi» tutor");
    expect(mayusculaInicial("Ya empieza bien")).toBe("Ya empieza bien");
    expect(mayusculaInicial("él")).toBe("Él");
    expect(mayusculaInicial("")).toBe("");
  });
  it("se aplica a todos los campos «texto» de una respuesta, y solo a esos", () => {
    const r = textosConMayuscula({ nombre: "x", preguntas: [{ codigo: "a", texto: "las clases", resultado: { texto: "otra" } }] });
    expect(r).toEqual({ nombre: "x", preguntas: [{ codigo: "a", texto: "Las clases", resultado: { texto: "Otra" } }] });
  });
});
