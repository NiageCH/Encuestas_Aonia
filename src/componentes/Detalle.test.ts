// Corrección del 03/11/2026: en Alumnado no se podía cambiar el cuestionario. El desplegable hacía dos cambios seguidos
// (el cuestionario y vaciar el grupo) y el segundo partía de la dirección vieja, así que borraba el primero.
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { cambiarFiltros } from "./Detalle";

// Lo mínimo del navegador que usan los filtros: la dirección, el historial y el aviso de cambio.
let avisos = 0;
beforeEach(() => {
  avisos = 0;
  const location = { hash: "" };
  (globalThis as unknown as { window: unknown }).window = {
    location,
    history: { replaceState: (_e: unknown, _t: string, u: string) => { location.hash = u; } },
    dispatchEvent: () => { avisos++; return true; },
  };
});
afterEach(() => { delete (globalThis as { window?: unknown }).window; });
const hash = () => (globalThis as unknown as { window: { location: { hash: string } } }).window.location.hash;
const ir = (h: string) => { (globalThis as unknown as { window: { location: { hash: string } } }).window.location.hash = h; };

describe("cambiar filtros de una pantalla", () => {
  it("Alumnado: elegir otro cuestionario y vaciar el grupo en el mismo cambio deja el cuestionario elegido", () => {
    ir("#/alumnos");
    cambiarFiltros("direccion", { cuestionario: "ALU_Y6Y9", grupo: null });
    cambiarFiltros("direccion", { grupo: null });
    expect(hash()).toBe("#/alumnos?cuestionario=ALU_Y6Y9");
  });
  it("lo mismo al llegar desde Inicio (?volver)", () => {
    ir("#/alumnos?volver=%23%2F");
    cambiarFiltros("direccion", { cuestionario: "ALU_Y6Y9", grupo: null });
    cambiarFiltros("direccion", { grupo: null });
    expect(hash()).toBe("#/alumnos?cuestionario=ALU_Y6Y9&volver=%23%2F");
  });
  it("elegir cuestionario y después grupo suma los dos; cambiar de cuestionario vacía el grupo", () => {
    ir("#/alumnos?cuestionario=ALU_Y6Y9");
    cambiarFiltros("coordinacion", { grupo: "Y7 A" });
    expect(hash()).toBe("#/alumnos?cuestionario=ALU_Y6Y9&grupo=Y7%20A");
    cambiarFiltros("coordinacion", { cuestionario: "ALU_Y10", etapa: null, grupo: null, bloque: null });
    expect(hash()).toBe("#/alumnos?cuestionario=ALU_Y10");
  });
  it("Familias y Personal: cambiar la etapa o el segmento no borra el bloque, y al revés", () => {
    ir("#/familias");
    cambiarFiltros("direccion", { bloque: "servicios" });
    cambiarFiltros("direccion", { etapa: "pai" });
    expect(hash()).toBe("#/familias?etapa=pai&bloque=servicios");
    ir("#/personal?segmento=docentes");
    cambiarFiltros("administrador", { bloque: "centro" });
    cambiarFiltros("administrador", { segmento: null });
    expect(hash()).toBe("#/personal?bloque=centro");
  });
  it("Informes: elegir docente o jefatura conserva el filtro del detalle y «volver»", () => {
    ir("#/informes/profesores?cuestionario=ALU_Y6Y9&asignatura=Matem%C3%A1ticas&volver=%23%2Falumnos");
    cambiarFiltros("coordinacion", { profesor: "12" });
    expect(hash()).toBe("#/informes/profesores?cuestionario=ALU_Y6Y9&asignatura=Matem%C3%A1ticas&profesor=12&volver=%23%2Falumnos");
    ir("#/informes/departamentos?jefe=3&departamento=Ciencias&ver=en-dep-detalle&volver=%23%2Fpersonal");
    cambiarFiltros("direccion", { jefe: "4", departamento: null });
    expect(hash()).toBe("#/informes/departamentos?jefe=4&volver=%23%2Fpersonal");
  });
  it("sin cambio real no se toca la dirección", () => {
    ir("#/familias?etapa=pai");
    cambiarFiltros("direccion", { etapa: "pai" });
    expect(avisos).toBe(0);
  });
});
