import { describe, expect, it } from "vitest";
import { PDFDocument } from "@cantoo/pdf-lib";
import { protegerPdf } from "./proteger";

async function pdfDePrueba(): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  doc.addPage().drawText("Media global 4,30");
  return doc.save();
}

describe("PDF protegido", () => {
  // Título, autor y asunto van cifrados dentro del PDF: se comprueban con un lector (PyMuPDF) en las capturas.
  it("va cifrado con AES-256 y se abre sin contraseña", async () => {
    const bytes = await protegerPdf(await pdfDePrueba(), { titulo: "Informe del profesor/a · Ana García" });
    const texto = new TextDecoder("latin1").decode(bytes);
    expect(texto).toContain("/Encrypt");
    expect(texto).toMatch(/\/V 5/);
    expect((await PDFDocument.load(bytes, { password: "" })).getPageCount()).toBe(1);
  });

  it("sin permiso para copiar ni editar (bits 5 y 4 del /P a cero), sí para imprimir", async () => {
    const texto = new TextDecoder("latin1").decode(await protegerPdf(await pdfDePrueba(), { titulo: "x" }));
    const p = Number(/\/P (-?\d+)/.exec(texto)![1]);
    expect(p & (1 << 4)).toBe(0);   // copiar (bit 5)
    expect(p & (1 << 3)).toBe(0);   // modificar (bit 4)
    expect(p & (1 << 2)).not.toBe(0);   // imprimir (bit 3)
  });

  it("cada PDF con su propia clave", async () => {
    const original = await pdfDePrueba();
    const a = new TextDecoder("latin1").decode(await protegerPdf(original, { titulo: "x" }));
    const b = new TextDecoder("latin1").decode(await protegerPdf(original, { titulo: "x" }));
    expect(/\/O <([0-9a-f]+)>/i.exec(a)?.[1] ?? /\/O \(([^)]*)\)/.exec(a)?.[1]).not.toBe(/\/O <([0-9a-f]+)>/i.exec(b)?.[1] ?? /\/O \(([^)]*)\)/.exec(b)?.[1]);
  });
});
