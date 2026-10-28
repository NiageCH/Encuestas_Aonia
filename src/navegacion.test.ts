import { describe, expect, it } from "vitest";
import { aHash, leerRuta, menu, nivelesPermitidos, permitida } from "./navegacion";

const ir = (hash: string, rol: "administrador" | "direccion" | "coordinacion") => aHash(leerRuta(hash, rol));

describe("menú de arriba", () => {
  it("Informes por persona va después de Personal y antes de Usuarios", () => {
    expect(menu("administrador")).toEqual(["/", "/alumnos", "/familias", "/personal", "/abiertas", "/informes", "/usuarios"]);
    expect(menu("direccion")).toEqual(["/", "/alumnos", "/familias", "/personal", "/abiertas", "/informes"]);
  });
  it("la coordinación no ve Personal ni Usuarios, sí Informes por persona", () => {
    expect(menu("coordinacion")).toEqual(["/", "/alumnos", "/familias", "/informes"]);
  });
});

describe("navegación de la coordinación de etapa", () => {
  it("Informes por persona la lleva directamente a Profesores", () => {
    expect(ir("#/informes", "coordinacion")).toBe("#/informes/profesores");
    expect(ir("#/informes/profesores", "coordinacion")).toBe("#/informes/profesores");
  });
  it("no llega a Dirección, Equipos ni Departamentos", () => {
    for (const nivel of ["direccion", "equipos", "departamentos"]) {
      expect(ir(`#/informes/${nivel}`, "coordinacion")).toBe("#/informes/profesores");
    }
    expect(nivelesPermitidos("coordinacion")).toEqual(["profesores"]);
  });
  it("Personal (y sus direcciones antiguas) la llevan a Profesores", () => {
    expect(ir("#/personal", "coordinacion")).toBe("#/informes/profesores");
    expect(ir("#/personal/encuesta", "coordinacion")).toBe("#/informes/profesores");
    expect(ir("#/personal/informes/direccion", "coordinacion")).toBe("#/informes/profesores");
    expect(ir("#/profesorado", "coordinacion")).toBe("#/informes/profesores");
    expect(ir("#/responsables", "coordinacion")).toBe("#/informes/profesores");
  });
  it("no ve Usuarios", () => {
    expect(ir("#/usuarios", "coordinacion")).toBe("#/");
  });
  it("sí ve inicio, alumnos y familias", () => {
    expect(ir("#/alumnos", "coordinacion")).toBe("#/alumnos");
    expect(ir("#/familias", "coordinacion")).toBe("#/familias");
    expect(ir("#/", "coordinacion")).toBe("#/");
  });
});

describe("navegación de dirección y administración", () => {
  it("Personal es la encuesta de personal", () => {
    expect(ir("#/personal", "direccion")).toBe("#/personal");
    expect(ir("#/personal/encuesta", "direccion")).toBe("#/personal");
  });
  it("Informes por persona: todos los niveles, en orden jerárquico, empezando por Dirección", () => {
    expect(nivelesPermitidos("direccion")).toEqual(["direccion", "equipos", "departamentos", "profesores"]);
    expect(nivelesPermitidos("administrador")).toEqual(["direccion", "equipos", "departamentos", "profesores", "envio"]);
    expect(ir("#/informes", "direccion")).toBe("#/informes/direccion");
    expect(ir("#/informes/departamentos", "direccion")).toBe("#/informes/departamentos");
    expect(ir("#/informes/no-existe", "direccion")).toBe("#/informes/direccion");
  });
  it("las direcciones antiguas llevan a su nuevo sitio", () => {
    expect(ir("#/personal/informes/equipos", "direccion")).toBe("#/informes/equipos");
    expect(ir("#/personal/informes", "direccion")).toBe("#/informes/direccion");
    expect(ir("#/profesorado", "direccion")).toBe("#/informes/profesores");
    expect(ir("#/responsables", "direccion")).toBe("#/informes/direccion");
  });
  it("Usuarios es solo para administradores", () => {
    expect(ir("#/usuarios", "direccion")).toBe("#/");
    expect(ir("#/usuarios", "administrador")).toBe("#/usuarios");
    expect(permitida({ seccion: "/usuarios" }, "administrador")).toBe(true);
  });
  it("una dirección desconocida lleva a inicio", () => {
    expect(ir("#/no-existe", "direccion")).toBe("#/");
    expect(ir("#access_token=x&type=invite", "direccion")).toBe("#/");
  });
});

describe("registro de descargas", () => {
  it("pestaña de Accesos, solo para administración", () => {
    expect(ir("#/usuarios/descargas", "administrador")).toBe("#/usuarios/descargas");
    expect(ir("#/usuarios/otra", "administrador")).toBe("#/usuarios");
    expect(ir("#/usuarios/descargas", "direccion")).toBe("#/");
    expect(ir("#/usuarios/descargas", "coordinacion")).toBe("#/");
  });
});

describe("respuestas abiertas y envío de informes (§7.9 y §7.10)", () => {
  it("las respuestas abiertas, solo Dirección y administración", () => {
    expect(ir("#/abiertas", "direccion")).toBe("#/abiertas");
    expect(ir("#/abiertas", "administrador")).toBe("#/abiertas");
    expect(ir("#/abiertas", "coordinacion")).toBe("#/");
  });
  it("el envío al profesorado, solo administración", () => {
    expect(ir("#/informes/envio", "administrador")).toBe("#/informes/envio");
    expect(ir("#/informes/envio", "direccion")).toBe("#/informes/direccion");
    expect(ir("#/informes/envio", "coordinacion")).toBe("#/informes/profesores");
  });
});
