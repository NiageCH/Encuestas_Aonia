import { describe, expect, it } from "vitest";
import { estadoDeError, hayResultados, nivelAcceso, puedeVerResultados } from "./acceso";

const token = (aal: string) => `x.${btoa(JSON.stringify({ aal })).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_")}.y`;

describe("acceso a los resultados", () => {
  it("lee el nivel de la sesión del token", () => {
    expect(nivelAcceso(token("aal2"))).toBe("aal2");
    expect(nivelAcceso(token("aal1"))).toBe("aal1");
    expect(nivelAcceso("basura")).toBeNull();
    expect(nivelAcceso(undefined)).toBeNull();
  });
  it("un administrador sin doble factor no puede pedir resultados", () => {
    expect(puedeVerResultados("administrador", true, true, "aal1")).toBe(false);
    expect(puedeVerResultados("administrador", true, true, "aal2")).toBe(true);
  });
  it("mientras no se sabe si el doble factor es obligatorio, tampoco", () => {
    expect(puedeVerResultados("administrador", true, undefined, "aal2")).toBe(false);
  });
  it("en local, con el doble factor desactivado, el administrador sí", () => {
    expect(puedeVerResultados("administrador", true, false, "aal1")).toBe(true);
  });
  it("dirección y coordinación no necesitan doble factor; nadie desactivado", () => {
    expect(puedeVerResultados("direccion", true, true, "aal1")).toBe(true);
    expect(puedeVerResultados("coordinacion", true, true, "aal1")).toBe(true);
    expect(puedeVerResultados("direccion", false, true, "aal1")).toBe(false);
  });
  it("una negativa del servidor no es «sin datos»", () => {
    expect(estadoDeError({ code: "42501", message: "Doble factor obligatorio para las cuentas de administración" })).toEqual({ estado: "sin_acceso" });
    expect(estadoDeError(new Error("Failed to fetch"))).toEqual({ estado: "error" });
    expect(hayResultados({ estado: "sin_acceso" }, ["familias"])).toBe(false);
  });
  it("el estado vacío solo con una respuesta real sin ese colectivo", () => {
    expect(hayResultados({ estado: "cargando" }, ["familias"])).toBe(true);
    expect(hayResultados({ estado: "listo", colectivos: ["alumnos", "familias"] }, ["familias"])).toBe(true);
    expect(hayResultados({ estado: "listo", colectivos: ["alumnos"] }, ["personal"])).toBe(false);
  });
});

import { sesionRechazada } from "./acceso";

describe("sesionRechazada", () => {
  it("cierra la sesión si el servidor la rechaza", () => {
    expect(sesionRechazada({ status: 401 })).toBe(true);
    expect(sesionRechazada({ status: 403 })).toBe(true);
    expect(sesionRechazada({ name: "AuthSessionMissingError" })).toBe(true);
  });
  it("no la cierra por un fallo de red o del servidor", () => {
    expect(sesionRechazada({ name: "AuthRetryableFetchError" })).toBe(false);
    expect(sesionRechazada({ status: 500 })).toBe(false);
  });
});
