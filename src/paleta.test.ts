import { describe, expect, it } from "vitest";
import { ESCALA_1_6, PALETA, aclarar, textoSobre, tonosEscala, variablesCss } from "./paleta";

function contraste(a: string, b: string): number {
  const l = (hex: string) => {
    const n = parseInt(hex.slice(1), 16);
    const [r, g, bl] = [n >> 16, (n >> 8) & 255, n & 255].map((v) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; });
    return 0.2126 * r + 0.7152 * g + 0.0722 * bl;
  };
  const [x, y] = [l(a), l(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
}

describe("paleta", () => {
  it("escala de 1 a 6: el 1 y el 6 son los colores puros; 2-3 y 4-5, cada vez más claros hacia el centro", () => {
    expect(ESCALA_1_6[0]).toBe(PALETA.negativo);
    expect(ESCALA_1_6[5]).toBe(PALETA.positivo);
    expect(ESCALA_1_6[1]).toBe(aclarar(PALETA.negativo, 70));
    expect(ESCALA_1_6[2]).toBe(aclarar(PALETA.negativo, 40));
    expect(ESCALA_1_6[3]).toBe(aclarar(PALETA.positivo, 40));
    expect(ESCALA_1_6[4]).toBe(aclarar(PALETA.positivo, 70));
  });
  it("otras escalas, en proporción: impar con centro neutro, y de 1 a 10 con cinco tonos por lado", () => {
    const e3 = tonosEscala(1, 3);
    expect(e3).toEqual([PALETA.negativo, aclarar(PALETA.neutro, 45), PALETA.positivo]);
    const e10 = tonosEscala(1, 10);
    expect(e10).toHaveLength(10);
    expect(e10[0]).toBe(PALETA.negativo);
    expect(e10[9]).toBe(PALETA.positivo);
    expect(e10[4]).toBe(aclarar(PALETA.negativo, 40));
  });
  it("solo petróleo y positivo sirven como texto sobre blanco (contraste de 4,5 o más)", () => {
    expect(contraste(PALETA.grafico1, "#FFFFFF")).toBeGreaterThanOrEqual(4.5);
    expect(contraste(PALETA.positivo, "#FFFFFF")).toBeGreaterThanOrEqual(4.5);
    for (const c of [PALETA.grafico2, PALETA.grafico3]) expect(contraste(c, "#FFFFFF")).toBeLessThan(4.5);
  });
  it("el texto sobre cada tono de la escala tiene contraste suficiente", () => {
    for (const c of ESCALA_1_6) expect(contraste(c, textoSobre(c))).toBeGreaterThanOrEqual(3);
  });
  it("las variables CSS llevan el prefijo en-", () => {
    expect(Object.keys(variablesCss()).every((k) => k.startsWith("--en-"))).toBe(true);
  });
});
