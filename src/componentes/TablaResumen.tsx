// Tablas de los informes de tutoría y de servicios (§7.12 y §7.13), en pantalla y en el enlace personal. El PDF pinta
// las mismas (src/data/tablasResumen.ts): media y número de valoraciones, o una nota en lugar de un hueco.

import type { TablaResumen as Tabla, ValorResumen } from "../data/tablasResumen";
import { textoNota } from "../etiquetas";
import * as f from "../formato";
import { t } from "../i18n";
import { MarcaMenos5 } from "./Oculto";
import { NotasTabla } from "./TablaPreguntasProfesor";

export function TablaResumen({ tabla }: { tabla: Tabla }) {
  return (
    <div className="card" style={{ marginTop: ".9rem" }}>
      <h3>{tabla.titulo}</h3>
      <p className="en-hint">{tabla.lead}</p>
      <div className="tbl-wrap">
        <table className="doc-table en-tabla-prof en-tabla-resumen">
          <thead>
            <tr><th>{t.pregunta}</th>{tabla.columnas.map((c) => <th key={c}>{c}</th>)}</tr>
          </thead>
          <tbody>
            {tabla.filas.map((x) => (
              <tr key={x.codigo} className={x.secundaria ? "en-fila-secundaria" : undefined}>
                <td>{x.texto}</td>
                {x.valores.map((v, i) => (
                  <td key={i} className="n" data-etiqueta={tabla.columnas[i]}><Valor v={v} fuerte={i === 0} /></td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {tabla.referencia && (
        <p className="en-hint en-referencia">{tabla.referencia.texto}: {"nota" in tabla.referencia.valor
          ? <span className="en-oculto">{textoNota(tabla.referencia.valor)}</span>
          : `${f.media(tabla.referencia.valor.media)} (${t.res_respuestas(f.recuento(tabla.referencia.valor.n))})`}</p>
      )}
      <NotasTabla notas={tabla.notas} />
    </div>
  );
}

export function Valor({ v, fuerte }: { v: ValorResumen; fuerte: boolean }) {
  if ("nota" in v) return <span className="en-oculto">{textoNota(v)}</span>;
  const m = f.media(v.media);
  return (
    <>
      {fuerte ? <strong>{m}</strong> : m}
      <small className="en-n">{t.res_respuestas(f.recuento(v.n))}</small>
      {v.menos_de_5 ? <MarcaMenos5 fila={{ menos_de_5: true }} /> : null}
    </>
  );
}
