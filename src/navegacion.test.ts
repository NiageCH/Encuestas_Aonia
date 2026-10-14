import { describe, expect, it } from "vitest";
import { aHash, leerRuta, nivelesPermitidos, permitida } from "./navegacion";

const ir = (hash: string, rol: "administrador" | "direccion" | "coordinacion") => aHash(leerRuta(hash, rol));

describe("navegación de la coordinación de etapa", () => {
  it("entra en Personal pero solo llega a Informes por persona → Profesores", () => {
    expect(ir("#/personal", "coordinacion")).toBe("#/personal/informes/profesores");
    expect(ir("#/personal/encuesta", "coordinacion")).toBe("#/personal/informes/profesores");
    expect(ir("#/personal/informes", "coordinacion")).toBe("#/personal/informes/profesores");
  });
  it("no llega a Dirección, Equipos ni Departamentos", () => {
    for (const nivel of ["direccion", "equipos", "departamentos"]) {
      expect(ir(`#/personal/informes/${nivel}`, "coordinacion")).toBe("#/personal/informes/profesores");
    }
    expect(nivelesPermitidos("coordinacion")).toEqual(["profesores"]);
  });
  it("las direcciones antiguas la llevan a Profesores", () => {
    expect(ir("#/profesorado", "coordinacion")).toBe("#/personal/informes/profesores");
    expect(ir("#/responsables", "coordinacion")).toBe("#/personal/informes/profesores");
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
  it("Personal lleva a la encuesta de personal", () => {
    expect(ir("#/personal", "direccion")).toBe("#/personal/encuesta");
  });
  it("ve todos los niveles, en orden jerárquico", () => {
    expect(nivelesPermitidos("direccion")).toEqual(["direccion", "equipos", "departamentos", "profesores"]);
    expect(ir("#/personal/informes/departamentos", "direccion")).toBe("#/personal/informes/departamentos");
    expect(ir("#/personal/informes", "direccion")).toBe("#/personal/informes/direccion");
  });
  it("las direcciones antiguas llevan a su nuevo sitio", () => {
    expect(ir("#/profesorado", "direccion")).toBe("#/personal/informes/profesores");
    expect(ir("#/responsables", "direccion")).toBe("#/personal/informes/direccion");
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
