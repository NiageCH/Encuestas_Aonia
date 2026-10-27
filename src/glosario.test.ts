import { describe, expect, it } from "vitest";
import { DESCARTADOS, textosDe } from "./glosario";
import { I18N } from "./i18n";

describe("glosario (docs/GLOSARIO.md)", () => {
  it("ningún texto de la interfaz usa un término descartado", () => {
    const fallos = textosDe(I18N.es).flatMap(([clave, texto]) =>
      DESCARTADOS.filter((d) => d.patron.test(texto)).map((d) => `${clave}: «${texto.slice(0, 90)}» → usar ${d.usar}`));
    expect(fallos).toEqual([]);
  });

  it("detecta los términos descartados", () => {
    const encontrados = (s: string) => DESCARTADOS.filter((d) => d.patron.test(s)).length;
    expect(encontrados("Resultados de los alumnos")).toBe(1);
    expect(encontrados("Informe del profesor")).toBe(1);
    expect(encontrados("Informe del profesor/a")).toBe(0);
    expect(encontrados("Puntos fuertes")).toBe(1);
    expect(encontrados("sí, con entusiasmo")).toBe(1);
    expect(encontrados("Alumnado y profesorado")).toBe(0);
    expect(encontrados("Jefes de departamento")).toBe(1);
    expect(encontrados("Media del colegio")).toBe(1);
    expect(encontrados("Media del Colegio")).toBe(0);
    expect(encontrados("Invitar usuario")).toBe(1);
    expect(encontrados("Bienvenida o bienvenido")).toBe(1);
    expect(encontrados("Te damos la bienvenida")).toBe(0);
  });
});
