// Pestaña «Descargas» de Accesos: el registro de cada PDF, CSV o ZIP descargado, con filtros, búsqueda por código y
// exportación a CSV (con la misma cabecera de confidencialidad). Solo administración, y en solo lectura: el servidor no
// deja cambiar ni borrar nada del registro.

import { useEffect, useState, type FormEvent } from "react";
import { descargas, TIPOS_DESCARGA, type FiltrosDescargas, type FilaDescarga } from "../data/descargas";
import { exportar } from "../exportacion/exportar";
import { txt, type Exportacion } from "../exportacion/modelo";
import { fechaExportacion } from "../exportacion/csv";
import { t } from "../i18n";

const textoFiltros = (f?: Record<string, string>) =>
  f && Object.keys(f).length ? Object.entries(f).map(([k, v]) => `${k}: ${v}`).join(" · ") : t.dsc_sin_filtros;

export function Descargas() {
  const [filtros, setFiltros] = useState<FiltrosDescargas>({});
  const [aplicados, setAplicados] = useState<FiltrosDescargas>({});
  const [datos, setDatos] = useState<Awaited<ReturnType<typeof descargas>> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [exportando, setExportando] = useState(false);

  async function buscar(f: FiltrosDescargas) {
    setError(null);
    try { setDatos(await descargas(f)); setAplicados(f); } catch (e) { setError((e as Error).message || t.error_datos); }
  }
  useEffect(() => { buscar({}); }, []);

  const cambiar = (k: keyof FiltrosDescargas, v: string) => setFiltros({ ...filtros, [k]: v || undefined });
  const enviar = (e: FormEvent) => { e.preventDefault(); buscar(filtros); };

  /** Lo filtrado, con la misma cabecera de confidencialidad que cualquier CSV (y queda en el propio registro). */
  async function exportarCsv() {
    if (!datos) return;
    const persona = datos.personas.find((p) => p.id === aplicados.persona)?.nombre;
    const activos: [string, string][] = [
      ...(persona ? [[t.dsc_persona, persona] as [string, string]] : []),
      ...(aplicados.tipo ? [[t.dsc_tipo, t.dsc_tipos[aplicados.tipo]] as [string, string]] : []),
      ...(aplicados.desde ? [[t.dsc_desde, aplicados.desde] as [string, string]] : []),
      ...(aplicados.hasta ? [[t.dsc_hasta, aplicados.hasta] as [string, string]] : []),
      ...(aplicados.objeto ? [[t.dsc_objeto, aplicados.objeto] as [string, string]] : []),
      ...(aplicados.codigo ? [[t.dsc_codigo, aplicados.codigo] as [string, string]] : []),
    ];
    const e: Exportacion = {
      vista: "descargas", titulo: t.dsc_titulo, filtros: activos, sinCurso: true,
      archivo: ["Registro_descargas", new Date().toISOString().slice(0, 10)],
      tablas: [{
        titulo: t.dsc_titulo,
        columnas: [t.dsc_col_fecha, t.dsc_col_persona, t.dsc_col_correo, t.dsc_col_tipo, t.dsc_col_objeto, t.dsc_col_filtros, t.dsc_col_codigo, t.dsc_col_informes],
        filas: datos.filas.map((d) => [
          txt(fechaExportacion(new Date(d.fecha))), txt(d.persona), txt(d.correo ?? "—"), txt(t.dsc_tipos[d.tipo] ?? d.tipo), txt(d.objeto),
          txt(textoFiltros(d.filtros)), txt(d.codigo), txt(d.informes?.map((i) => `${i.objeto} (${i.codigo})`).join(" · ") || "—"),
        ]),
      }],
      notas: [],
    };
    setExportando(true);
    try { await exportar(e, "csv"); await buscar(aplicados); } catch (x) { setError((x as Error).message || t.error_datos); } finally { setExportando(false); }
  }

  const codigo = (aplicados.codigo ?? "").trim().toUpperCase();
  return (
    <>
      <h2 className="section-title">{t.dsc_titulo}</h2>
      <p className="sec-lead">{t.dsc_lead}</p>
      <form className="card en-filters en-dsc-filtros" onSubmit={enviar}>
        <label>{t.dsc_persona}
          <span className="en-select"><select value={filtros.persona ?? ""} onChange={(e) => cambiar("persona", e.target.value)}>
            <option value="">{t.dsc_todas}</option>
            {datos?.personas.map((p) => <option key={p.id} value={p.id}>{p.nombre}</option>)}
          </select></span>
        </label>
        <label>{t.dsc_tipo}
          <span className="en-select"><select value={filtros.tipo ?? ""} onChange={(e) => cambiar("tipo", e.target.value)}>
            <option value="">{t.dsc_todos}</option>
            {TIPOS_DESCARGA.map((x) => <option key={x} value={x}>{t.dsc_tipos[x]}</option>)}
          </select></span>
        </label>
        <label>{t.dsc_desde}<input type="date" value={filtros.desde ?? ""} onChange={(e) => cambiar("desde", e.target.value)} /></label>
        <label>{t.dsc_hasta}<input type="date" value={filtros.hasta ?? ""} onChange={(e) => cambiar("hasta", e.target.value)} /></label>
        <label>{t.dsc_objeto}<input value={filtros.objeto ?? ""} placeholder={t.dsc_objeto_ph} onChange={(e) => cambiar("objeto", e.target.value)} /></label>
        <label>{t.dsc_codigo}<input value={filtros.codigo ?? ""} placeholder={t.dsc_codigo_ph} onChange={(e) => cambiar("codigo", e.target.value)} /></label>
        <div className="en-botonera en-dsc-botones">
          <button type="submit" className="btn primary">{t.dsc_buscar}</button>
          <button type="button" className="btn" onClick={() => { setFiltros({}); buscar({}); }}>{t.dsc_limpiar}</button>
        </div>
      </form>
      {error && <p className="notice en-alerta en-alerta-neg" role="alert">{error}</p>}
      {!datos && !error && <p className="en-cargando">{t.cargando}</p>}
      {datos && (
        <div className="card">
          <div className="en-dsc-cab">
            <p className="en-hint" role="status" style={{ margin: 0 }}>{t.dsc_total(datos.filas.length, datos.total)}</p>
            <button type="button" className="btn" onClick={exportarCsv} disabled={exportando || datos.filas.length === 0}>⬇ {t.dsc_exportar}</button>
          </div>
          {datos.filas.length === 0 ? <p className="en-hint">{t.dsc_vacio}</p> : (
            <div className="tbl-wrap">
              <table className="doc-table en-tabla-usr en-tabla-dsc">
                <thead><tr><th>{t.dsc_col_fecha}</th><th>{t.dsc_col_persona}</th><th>{t.dsc_col_tipo}</th><th>{t.dsc_col_objeto}</th><th>{t.dsc_col_filtros}</th><th>{t.dsc_col_codigo}</th></tr></thead>
                <tbody>{datos.filas.map((d) => <Fila key={d.codigo} d={d} codigo={codigo} />)}</tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </>
  );
}

function Fila({ d, codigo }: { d: FilaDescarga; codigo: string }) {
  const marcado = (c: string) => (codigo && c === codigo ? <mark>{c}</mark> : c);
  const dentro = !!codigo && d.codigo !== codigo && d.informes?.some((i) => i.codigo === codigo);
  return (
    <tr>
      <td data-etiqueta={t.dsc_col_fecha} className="en-sin-partir">{fechaExportacion(new Date(d.fecha))}</td>
      <td data-etiqueta={t.dsc_col_persona}><strong>{d.persona}</strong>{d.correo && <><br /><small className="en-hint">{d.correo}</small></>}</td>
      <td data-etiqueta={t.dsc_col_tipo}>{t.dsc_tipos[d.tipo] ?? d.tipo}</td>
      <td data-etiqueta={t.dsc_col_objeto}>
        {d.objeto}{d.archivo && <><br /><small className="en-hint">{d.archivo}</small></>}
        {d.informes && (
          <details open={dentro} className="en-dsc-zip">
            <summary>{t.dsc_informes_zip(d.informes.length)}</summary>
            <ul>{d.informes.map((i) => <li key={i.codigo}>{i.objeto} · <code>{marcado(i.codigo)}</code></li>)}</ul>
          </details>
        )}
      </td>
      <td data-etiqueta={t.dsc_col_filtros}>{textoFiltros(d.filtros)}</td>
      <td data-etiqueta={t.dsc_col_codigo}><code className="en-dsc-codigo">{marcado(d.codigo)}</code></td>
    </tr>
  );
}
