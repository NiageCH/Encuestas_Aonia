// Paleta de gráficos, indicadores y alertas (decisión del 26/10/2026). Único sitio donde se definen estos colores:
// la web los recibe como variables CSS --en-* en :root (aplicarPaleta, al arrancar) y los PDF los importan de aquí.
// El resto del estilo (fondo, textos, cabecera, botones) sigue siendo el de la intranet (:root de intranet.css).
//
// Reglas de uso (CLAUDE.md, regla 6, y especificación):
// - Series y categorías: grafico1 a grafico4, en ese orden. Medias y barras simples: grafico1.
// - Escalas: los valores bajos en tonos de «negativo» (más intenso en el extremo) y los altos en tonos de «positivo»;
//   NS/NC en gris. Recomendación: no en negativo, neutral en neutro y sí en positivo.
// - Texto sobre blanco: solo grafico1 y positivo. Las alertas llevan el color en el borde, el icono o un fondo suave,
//   con el texto en oscuro. Salvia y lavanda (grafico2 y grafico3) nunca como único elemento sin etiqueta.

export const PALETA = {
  grafico1: "#376878",   // azul petróleo (principal)
  grafico2: "#8DA9A5",   // verde salvia
  grafico3: "#9997B8",   // lavanda grisáceo
  grafico4: "#597D9A",   // azul acero
  positivo: "#397F78",
  negativo: "#B66579",
  neutro: "#71869A",
  nsnc: "#C3CAD2",       // gris de NS/NC
  texto: "#1A2C4A",      // texto oscuro de la intranet (--ink), para alertas y etiquetas
} as const;

/** Mezcla un color con blanco: pct = 100 es el color puro. */
export function aclarar(hex: string, pct: number): string {
  const n = parseInt(hex.slice(1), 16);
  const c = [n >> 16, (n >> 8) & 255, n & 255].map((v) => Math.round(255 - ((255 - v) * pct) / 100));
  return "#" + c.map((v) => v.toString(16).padStart(2, "0")).join("").toUpperCase();
}

/** Intensidad del tono más claro de cada lado (el más cercano al centro); el extremo es el color puro. */
const INTENSIDAD_MINIMA = 40;

/**
 * Tonos de una escala de min a max: la mitad baja en negativo (más intenso en min), la alta en positivo (más intenso
 * en max). Con un número impar de valores, el central es neutro. Para escalas largas se reparten las intensidades
 * en proporción.
 */
export function tonosEscala(min: number, max: number): string[] {
  const total = max - min + 1;
  const mitad = Math.floor(total / 2);
  const intensidad = (i: number) => (mitad <= 1 ? 100 : Math.round(100 - ((100 - INTENSIDAD_MINIMA) * i) / (mitad - 1)));
  const bajos = Array.from({ length: mitad }, (_, i) => aclarar(PALETA.negativo, intensidad(i)));
  const altos = Array.from({ length: mitad }, (_, i) => aclarar(PALETA.positivo, intensidad(i))).reverse();
  return total % 2 ? [...bajos, aclarar(PALETA.neutro, 45), ...altos] : [...bajos, ...altos];
}

/** ¿Texto blanco o texto oscuro sobre este fondo? (contraste según WCAG) */
export function textoSobre(hex: string): string {
  const n = parseInt(hex.slice(1), 16);
  const lin = [n >> 16, (n >> 8) & 255, n & 255].map((v) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; });
  const l = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
  return (1.05) / (l + 0.05) >= 4.5 ? "#FFFFFF" : PALETA.texto;
}

/** Escala de 1 a 6 (la de todas las encuestas de 2025/26). */
export const ESCALA_1_6 = tonosEscala(1, 6);

/** Variables CSS: --en-grafico-1..4, --en-positivo, --en-negativo, --en-neutro, --en-nsnc, sus fondos suaves y los
 *  tonos de la escala de 1 a 6 (--en-escala-1..6), con el color de texto que les corresponde. */
export function variablesCss(): Record<string, string> {
  const v: Record<string, string> = {
    "--en-grafico-1": PALETA.grafico1, "--en-grafico-2": PALETA.grafico2,
    "--en-grafico-3": PALETA.grafico3, "--en-grafico-4": PALETA.grafico4,
    "--en-positivo": PALETA.positivo, "--en-negativo": PALETA.negativo, "--en-neutro": PALETA.neutro,
    "--en-nsnc": PALETA.nsnc, "--en-texto": PALETA.texto,
    "--en-positivo-suave": aclarar(PALETA.positivo, 10), "--en-negativo-suave": aclarar(PALETA.negativo, 10),
    "--en-neutro-suave": aclarar(PALETA.neutro, 10),
    "--en-positivo-texto": textoSobre(PALETA.positivo), "--en-negativo-texto": textoSobre(PALETA.negativo),
    "--en-neutro-texto": textoSobre(PALETA.neutro),
  };
  ESCALA_1_6.forEach((c, i) => { v[`--en-escala-${i + 1}`] = c; v[`--en-escala-${i + 1}-texto`] = textoSobre(c); });
  return v;
}

export function aplicarPaleta(raiz: HTMLElement = document.documentElement): void {
  for (const [k, valor] of Object.entries(variablesCss())) raiz.style.setProperty(k, valor);
}
