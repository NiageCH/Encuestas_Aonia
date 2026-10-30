import { describe, expect, it } from "vitest";
import { conCambios, destino, sinVolver, soloFiltros } from "./detalle";
import { escalaAlumnos } from "./escalas";
import { t } from "./i18n";
import { aHash, leerRuta } from "./navegacion";

describe("filtros en la dirección de la página", () => {
  it("se leen y se vuelven a escribir igual (en el orden de cada pantalla)", () => {
    const h = "#/alumnos?cuestionario=ALU_Y6Y9&grupo=Y7%20A&bloque=servicios";
    expect(leerRuta(h, "direccion")).toEqual({ seccion: "/alumnos", filtro: { cuestionario: "ALU_Y6Y9", grupo: "Y7 A", bloque: "servicios" } });
    expect(aHash(leerRuta(h, "direccion"))).toBe(h);
    expect(aHash(leerRuta("#/alumnos?grupo=Y7%20A&cuestionario=ALU_Y6Y9", "direccion"))).toBe("#/alumnos?cuestionario=ALU_Y6Y9&grupo=Y7%20A");
  });
  it("las claves que una pantalla no acepta se descartan", () => {
    expect(aHash(leerRuta("#/familias?etapa=pai&docente=si&curso=2024", "direccion"))).toBe("#/familias?etapa=pai");
    expect(aHash(leerRuta("#/abiertas?pregunta=x", "direccion"))).toBe("#/abiertas");
  });
  it("una dirección mal escrita no rompe la navegación", () => {
    expect(aHash(leerRuta("#/familias?etapa=%E0%A4%A", "direccion"))).toBe("#/familias");
    expect(aHash(leerRuta("#/familias?=x&etapa", "direccion"))).toBe("#/familias");
  });
  it("los filtros no viajan a otra pantalla cuando el rol es redirigido", () => {
    expect(aHash(leerRuta("#/personal?segmento=docentes", "coordinacion"))).toBe("#/informes/profesores");
    expect(aHash(leerRuta("#/informes/departamentos?departamento=Ciencias", "coordinacion"))).toBe("#/informes/profesores");
    expect(aHash(leerRuta("#/profesorado?asignatura=Lengua", "direccion"))).toBe("#/informes/profesores");
  });
});

describe("destinos del detalle según el rol", () => {
  const desde = "#/personal?segmento=docentes";
  it("Dirección y administración: de un departamento a su informe de jefatura, con «volver»", () => {
    const d = destino({ seccion: "/informes", nivel: "departamentos", filtro: { jefe: "7", departamento: "Ciencias" } }, "direccion", desde);
    expect(d).toBe("#/informes/departamentos?jefe=7&departamento=Ciencias&volver=%23%2Fpersonal%3Fsegmento%3Ddocentes");
    expect(leerRuta(d!, "direccion").filtro?.volver).toBe(desde);
    expect(destino({ seccion: "/informes", nivel: "departamentos" }, "administrador", desde)).toBeDefined();
  });
  it("la coordinación nunca recibe destinos de pantallas que no tiene", () => {
    expect(destino({ seccion: "/personal", filtro: { segmento: "docentes" } }, "coordinacion", "#/")).toBeUndefined();
    expect(destino({ seccion: "/informes", nivel: "departamentos", filtro: { departamento: "Ciencias" } }, "coordinacion", "#/")).toBeUndefined();
    expect(destino({ seccion: "/informes", nivel: "equipos" }, "coordinacion", "#/")).toBeUndefined();
    expect(destino({ seccion: "/abiertas" }, "coordinacion", "#/")).toBeUndefined();
  });
  it("la coordinación sí: alumnado, familias y el profesorado de una asignatura", () => {
    expect(destino({ seccion: "/alumnos", filtro: { grupo: "Y7 A" } }, "coordinacion", "#/alumnos")).toBe("#/alumnos?grupo=Y7%20A&volver=%23%2Falumnos");
    expect(destino({ seccion: "/familias", filtro: { bloque: "centro", ver: "en-detalle" } }, "coordinacion", "#/")).toBeDefined();
    expect(destino({ seccion: "/informes", nivel: "profesores", filtro: { cuestionario: "ALU_Y6Y9", asignatura: "Matemáticas" } },
      "coordinacion", "#/alumnos")).toBe("#/informes/profesores?cuestionario=ALU_Y6Y9&asignatura=Matem%C3%A1ticas&volver=%23%2Falumnos");
  });
  it("«volver» guarda un solo paso: el origen sin su propio «volver»", () => {
    expect(sinVolver("#/familias?etapa=pai&volver=%23%2F")).toBe("#/familias?etapa=pai");
    expect(sinVolver("#/familias?volver=%23%2F")).toBe("#/familias");
    const d = destino({ seccion: "/familias", filtro: { bloque: "centro" } }, "direccion", "#/familias?etapa=pai&volver=%23%2F");
    expect(leerRuta(d!, "direccion").filtro?.volver).toBe("#/familias?etapa=pai");
  });
  it("quitar el detalle deja solo los filtros", () => {
    expect(soloFiltros({ etapa: "pai", bloque: "centro", ver: "en-detalle", volver: "#/", pregunta: "x" })).toEqual({ etapa: "pai", bloque: "centro" });
    expect(conCambios({ etapa: "pai", bloque: "centro" }, { etapa: null, grupo: "Y7 A" })).toEqual({ bloque: "centro", grupo: "Y7 A" });
  });
});

describe("escalas del alumnado en el detalle por pregunta", () => {
  it("cada bloque con las palabras de su encuesta", () => {
    expect(escalaAlumnos("pai", "profesorado")).toBe(t.escala_frecuencia_alu);
    expect(escalaAlumnos("pai", "servicios")).toBe(t.escala_satisfaccion_alu);
    expect(escalaAlumnos("pai", "aprendizaje_convivencia")).toBe(t.escala_acuerdo_alu);
    expect(escalaAlumnos("pai", "mindfulness")).toBe(t.escala_acuerdo_alu_programas);
    expect(escalaAlumnos("primaria", "servicios")).toBe(t.escala_gusto_pri);
    expect(escalaAlumnos("primaria", "profesorado")).toBe(t.escala_frecuencia_pri);
    for (const e of [t.escala_frecuencia_alu, t.escala_satisfaccion_alu, t.escala_acuerdo_alu, t.escala_gusto_pri]) expect(e).toHaveLength(6);
  });
});
