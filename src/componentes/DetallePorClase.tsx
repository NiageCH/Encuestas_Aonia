// Detalle por clase del informe del profesor/a (§7.2): cada pregunta en cada clase (asignatura y grupo). En las dos
// versiones: la completa, con la marca «menos de 5»; la docente (también en el enlace personal), con el mínimo de 5 y
// la complementaria que aplica el servidor en cada celda.

import type { CeldaProfesor, InformeProfesor } from "../data/resultados";
import { claveClase, etiquetaClase } from "../etiquetas";
import * as f from "../formato";
import { t } from "../i18n";
import { deLaClase, notasDeCeldas } from "../data/tablaProfesor";
import { MarcaMenos5, Oculto } from "./Oculto";
import { NotasTabla } from "./TablaPreguntasProfesor";

export const mismaClase = (a: CeldaProfesor, b: CeldaProfesor) =>
  a.clave.cuestionario === b.clave.cuestionario && a.clave.grupo === b.clave.grupo && a.clave.asignatura === b.clave.asignatura;

export function DetallePorClase({ celdas, preguntas, abierta }: {
  celdas: CeldaProfesor[]; preguntas: InformeProfesor["preguntas"]; abierta?: string;
}) {
  return (
    <div className="card" id="en-por-clase" style={{ marginTop: ".9rem" }}>
      <h3>{t.prof_por_clase}</h3>
      <p className="en-hint">{t.prof_por_clase_lead}</p>
      {celdas.map((c) => (
        <details key={`${c.clave.cuestionario}-${c.clave.grupo}-${c.clave.asignatura}`} id={`en-clase-${claveClase(c)}`}
                 className={`en-clase-detalle${abierta === claveClase(c) ? " en-destacado" : ""}`} open={abierta === claveClase(c) || undefined}>
          <summary>
            <strong>{etiquetaClase(c)}</strong>
            {c.tipo === "compartida" && <small> · {t.prof_compartida_corto}</small>}
            {" · "}{c.suprimido ? <Oculto fila={c} /> : <>{f.media(c.media!)} · n {f.recuento(c.n!)}</>}
            <MarcaMenos5 fila={c} />
          </summary>
          {c.suprimido ? <p className="en-hint">{t.prof_clase_oculta}</p> : <div className="tbl-wrap">
            <table className="doc-table en-tabla-prof">
              <thead><tr><th>{t.pregunta}</th><th>{t.media}</th><th>n</th></tr></thead>
              <tbody>
                {deLaClase(preguntas, c).map(({ codigo, texto, x }) => (
                  <tr key={codigo}>
                    <td>{texto}</td>
                    <td className="n" data-etiqueta={t.media}>{x.suprimido ? <Oculto fila={x} /> : <strong>{f.media(x.media!)}</strong>}</td>
                    <td className="n" data-etiqueta="n">{!x.suprimido ? <>{f.recuento(x.n!)}<MarcaMenos5 fila={x} /></> : ""}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <NotasTabla notas={notasDeCeldas(deLaClase(preguntas, c).map(({ x }) => x))} />
          </div>}
        </details>
      ))}
    </div>
  );
}
