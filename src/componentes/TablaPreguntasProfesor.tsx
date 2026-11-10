// «Detalle por pregunta» del informe del profesor/a (§7.2), en pantalla y en el enlace personal: la media del docente,
// por pares en cada etapa cuando tiene varias, la de todo el profesorado como referencia y, en lugar de un hueco, una
// nota cuando una celda no lleva cifra. El PDF pinta la misma tabla (src/data/tablaProfesor.ts).

import type { InformeProfesor } from "../data/resultados";
import { tablaProfesor, type ValorTabla } from "../data/tablaProfesor";
import { columnaProfesor, textoNota } from "../etiquetas";
import * as f from "../formato";
import { t } from "../i18n";
import type { useAyuda } from "./Ayuda";
import { MarcaMenos5 } from "./Oculto";

export function TablaPreguntasProfesor({ informe, ayuda }: { informe: InformeProfesor; ayuda?: ReturnType<typeof useAyuda> }) {
  const tabla = tablaProfesor(informe);
  const completa = informe.version === "completa";
  const cols = tabla.columnas.map((c) => columnaProfesor(c, tabla, completa && !!informe.global.menos_de_5));
  // Cabecera: con pares, una fila con la etapa encima de «Este profesor/a» y «Todo el profesorado».
  const grupos: { texto?: string; titulo: string; ancho: number }[] = [];
  for (const c of cols.slice(1)) {
    const ultimo = grupos[grupos.length - 1];
    if (c.grupo && ultimo?.texto === c.grupo) ultimo.ancho++;
    else grupos.push({ texto: c.grupo, titulo: c.titulo, ancho: 1 });
  }

  return (
    <div className="card" style={{ marginTop: ".9rem" }}>
      <h3>{t.prof_detalle}</h3>
      <p className="en-hint">{t.prof_detalle_lead}{tabla.porPares ? ` ${t.prof_detalle_lead_pares}` : ""}</p>
      <div className="tbl-wrap">
        <table className={`doc-table en-tabla-prof${tabla.porPares ? " en-tabla-pares" : ""}`}>
          <thead>
            {tabla.porPares ? (
              <>
                <tr>
                  <th rowSpan={2}>{t.pregunta}</th>
                  <th rowSpan={2}>{cols[0].titulo}</th>
                  {grupos.map((g, i) => g.texto
                    ? <th key={i} colSpan={g.ancho} scope="colgroup" className="en-th-etapa">{g.texto}</th>
                    : <th key={i} rowSpan={2}>{g.titulo}</th>)}
                </tr>
                <tr>{cols.slice(1).filter((c) => c.grupo).map((c, i) => <th key={i}>{c.titulo}</th>)}</tr>
              </>
            ) : (
              <tr><th>{t.pregunta}</th>{cols.map((c, i) => <th key={i}>{c.titulo}</th>)}</tr>
            )}
          </thead>
          <tbody>
            {tabla.filas.map(({ codigo, texto, valores }, k) => (
              <tr key={codigo}>
                <td>{texto}</td>
                {valores.map((v, i) => (
                  <td key={i} className={`n${i === 0 && ayuda ? " en-con-ayuda" : ""}`} data-etiqueta={cols[i].etiqueta}
                      {...(i === 0 && ayuda ? ayuda(ayudaDocente(texto, v, informe.preguntas[k].resultado.global.n_valoraciones)) : {})}>
                    <Valor v={v} fuerte={i === 0} />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <NotasTabla notas={tabla.notas} />
    </div>
  );
}

function ayudaDocente(texto: string, v: ValorTabla, valoraciones?: number): string[] {
  if ("nota" in v) return [texto, t.prof_notas[v.nota]];
  return [texto, t.tip_media(f.media(v.media)), ...(valoraciones ? [t.tip_valoraciones(f.recuento(valoraciones))] : [])];
}

function Valor({ v, fuerte }: { v: ValorTabla; fuerte: boolean }) {
  if ("nota" in v) return <span className="en-oculto">{textoNota(v)}</span>;
  return <>{fuerte ? <strong>{f.media(v.media)}</strong> : f.media(v.media)}{v.menos_de_5 ? <MarcaMenos5 fila={{ menos_de_5: true }} /> : null}</>;
}

/** Notas de las celdas sin cifra, debajo de la tabla. */
export function NotasTabla({ notas }: { notas: (keyof typeof t.prof_notas)[] }) {
  if (notas.length === 0) return null;
  return (
    <ul className="en-notas-tabla" aria-label={t.prof_notas_titulo}>
      {notas.map((n) => <li key={n}>{t.prof_notas[n]}</li>)}
    </ul>
  );
}
