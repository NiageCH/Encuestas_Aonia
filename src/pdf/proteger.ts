// Propiedades y restricciones de cada PDF descargado: título, autor (el Colegio), asunto «Confidencial» y permisos que
// impiden copiar el texto, editar, anotar o reorganizar las páginas (sí se puede abrir sin contraseña e imprimir).
// react-pdf no cifra, así que el PDF ya generado se cifra aquí con @cantoo/pdf-lib (AES-256) y una contraseña de
// propietario aleatoria que no se guarda en ningún sitio.
//
// Es una restricción del formato: la respetan los lectores habituales (Acrobat, Vista Previa, navegadores), pero no
// impide una captura de pantalla. La protección de verdad es la marca de agua y el código de cada descarga.

import { PDFDocument } from "@cantoo/pdf-lib";
import { t } from "../i18n";

export interface Propiedades { titulo: string }

function contrasenaAleatoria(): string {
  const b = new Uint8Array(24);
  crypto.getRandomValues(b);
  return Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
}

export async function protegerPdf(original: Blob | Uint8Array, p: Propiedades): Promise<Uint8Array> {
  const bytes = original instanceof Uint8Array ? original : new Uint8Array(await original.arrayBuffer());
  const doc = await PDFDocument.load(bytes, { updateMetadata: false });
  doc.setTitle(p.titulo, { showInWindowTitleBar: true });
  doc.setAuthor(t.colegio);
  doc.setSubject(t.desc_asunto);
  doc.setCreator(t.brand_title);
  doc.setProducer(t.brand_title);
  doc.setLanguage("es-ES");
  doc.encrypt({
    ownerPassword: contrasenaAleatoria(),
    permissions: {
      printing: "highResolution", copying: false, modifying: false, annotating: false, fillingForms: false,
      documentAssembly: false,
      // Los lectores de pantalla pueden leer el texto (accesibilidad).
      contentAccessibility: true,
    },
  });
  return doc.save();
}
