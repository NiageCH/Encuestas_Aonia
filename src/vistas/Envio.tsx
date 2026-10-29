// Envío de los informes al profesorado (§7.10), en Informes por persona. Solo administración. Se elige a quién
// (individual, departamento, etapa, tramo o todos), se ve la lista de destinatarios y solo entonces se envía. Cada
// docente recibe un enlace personal a la versión docente de su informe, válido 7 días; abajo, los enlaces enviados con
// sus aperturas y descargas. En modo de pruebas todo va a un correo de Niage: nada al profesorado.

import { useEffect, useMemo, useState } from "react";
import {
  anularEnlace, enviados, enviar, jefaturas as cargarJefaturas, vistaPrevia,
  type Destinatario, type EnlaceEnviado, type Jefatura, type Seleccion, type TipoSeleccion, type VistaPrevia,
} from "../data/envio";
import { listarProfesores, type Profesor } from "../data/resultados";
import { t } from "../i18n";

const TIPOS: TipoSeleccion[] = ["docente", "departamento", "etapa", "tramo", "todos"];

/** «Profesor/a», «Jefatura de departamento: Ciencias» o «Equipo de Individuación: Y6 a Y9». */
export function textoInforme(x: Pick<Destinatario, "tipo" | "informe" | "tramo">): string {
  if (x.tipo === "profesor") return t.env_inf_profesor;
  if (x.tipo === "jefatura_departamento") return `${t.env_inf_departamento}${x.informe ? `: ${x.informe}` : ""}`;
  return `${t.env_inf_equipo}: ${t.env_tramos_todos[(x.tramo ?? x.informe ?? "") as keyof typeof t.env_tramos_todos] ?? x.tramo}`;
}
const ETAPAS = ["primaria", "pai", "bachillerato"];
const TRAMOS = ["y1_y5", "y6_y9", "y10_y12"];

const fechaHora = (iso: string) =>
  new Date(iso).toLocaleString("es-ES", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });

export function EnvioInformes() {
  const [profesores, setProfesores] = useState<Profesor[]>([]);
  const [listaJefaturas, setListaJefaturas] = useState<Jefatura[]>([]);
  const [destino, setDestino] = useState<"profesorado" | "jefaturas">("profesorado");
  const [tipo, setTipo] = useState<TipoSeleccion>("docente");
  const [valores, setValores] = useState<string[]>([]);
  const [busqueda, setBusqueda] = useState("");
  const [correoPrueba, setCorreoPrueba] = useState("");
  const [previa, setPrevia] = useState<VistaPrevia | null>(null);
  const [confirmando, setConfirmando] = useState(false);
  const [estado, setEstado] = useState<"" | "cargando" | "enviando">("");
  const [mensaje, setMensaje] = useState<{ ok: boolean; texto: string } | null>(null);
  const [lista, setLista] = useState<EnlaceEnviado[] | null>(null);

  const recargar = () => enviados().then(setLista).catch(() => setLista([]));
  useEffect(() => {
    listarProfesores().then(setProfesores).catch(() => {});
    cargarJefaturas().then(setListaJefaturas).catch(() => {});
    recargar();
  }, []);
  useEffect(() => { setTipo(destino === "jefaturas" ? "jefaturas" : "docente"); }, [destino]);
  // Cualquier cambio en la selección obliga a ver otra vez los destinatarios antes de enviar.
  useEffect(() => { setPrevia(null); setConfirmando(false); }, [tipo, valores, correoPrueba]);
  useEffect(() => { setValores([]); setBusqueda(""); }, [tipo]);

  const departamentos = useMemo(() => [...new Set(profesores.map((p) => p.departamento).filter(Boolean))].sort((a, b) => a!.localeCompare(b!, "es")) as string[], [profesores]);
  const opciones: { valor: string; texto: string }[] =
    tipo === "docente" ? profesores.filter((p) => !busqueda || `${p.nombre} ${p.apellidos}`.toLowerCase().includes(busqueda.toLowerCase()))
                           .map((p) => ({ valor: String(p.id), texto: `${p.apellidos}, ${p.nombre}` }))
    : tipo === "departamento" ? departamentos.map((d) => ({ valor: d, texto: d }))
    : tipo === "etapa" ? ETAPAS.map((e) => ({ valor: e, texto: t.etapas[e as keyof typeof t.etapas] }))
    : tipo === "tramo" ? TRAMOS.map((x) => ({ valor: x, texto: t.env_tramos[x as keyof typeof t.env_tramos] }))
    : tipo === "jefaturas" ? listaJefaturas.map((j) => ({
        valor: String(j.id),
        texto: `${j.apellidos}, ${j.nombre} (${[...j.departamentos, ...j.tramos.map((x) => t.env_tramos_todos[x as keyof typeof t.env_tramos_todos] ?? x)].join(", ")})`,
      }))
    : [];
  // Jefaturas sin marcar ninguna: todas.
  const seleccion: Seleccion = tipo === "todos" || (tipo === "jefaturas" && valores.length === 0) ? { tipo } : { tipo, valores };
  const listos = previa?.destinatarios.filter((d) => !d.aviso) ?? [];

  async function verDestinatarios() {
    setEstado("cargando"); setMensaje(null);
    try { setPrevia(await vistaPrevia(seleccion, correoPrueba.trim())); }
    catch (e) { setMensaje({ ok: false, texto: (e as Error).message || t.error_datos }); }
    finally { setEstado(""); }
  }

  async function confirmar() {
    setEstado("enviando"); setMensaje(null);
    try {
      const r = await enviar(seleccion, correoPrueba.trim());
      setMensaje({ ok: r.errores === 0, texto: t.env_resultado(r.enviados, r.errores) });
      setPrevia(null); setConfirmando(false);
      recargar();
    } catch (e) {
      setMensaje({ ok: false, texto: (e as Error).message || t.error_datos });
    } finally { setEstado(""); }
  }

  return (
    <>
      <h2 className="section-title">{t.env_titulo}</h2>
      <p className="sec-lead">{t.env_lead}</p>
      <p className="notice en-alerta">{t.env_pruebas}</p>

      <div className="card">
        <h3>{t.env_que}</h3>
        <div className="chips en-noprint" role="group" aria-label={t.env_que}>
          {(["profesorado", "jefaturas"] as const).map((x) => (
            <button key={x} className={`chip${destino === x ? " on" : ""}`} aria-pressed={destino === x} onClick={() => setDestino(x)}>{t.env_destinos[x]}</button>
          ))}
        </div>
        <p className="en-hint">{destino === "jefaturas" ? t.env_jefaturas_nota : t.env_profesorado_nota}</p>
        <h3>{t.env_quien}</h3>
        {destino === "profesorado" ? (
          <div className="chips en-noprint" role="group" aria-label={t.env_quien}>
            {TIPOS.map((x) => (
              <button key={x} className={`chip${tipo === x ? " on" : ""}`} aria-pressed={tipo === x} onClick={() => setTipo(x)}>{t.env_tipos[x]}</button>
            ))}
          </div>
        ) : <p className="en-hint">{t.env_jefaturas_elegir}</p>}
        {tipo === "docente" && (
          <label className="en-filters" style={{ display: "grid", marginTop: ".6rem" }}>
            <span>{t.prof_buscar}</span>
            <input type="search" className="en-input" value={busqueda} onChange={(e) => setBusqueda(e.target.value)} placeholder={t.prof_buscar_ph} />
          </label>
        )}
        {tipo !== "todos" && (
          <div className="en-env-opciones">
            {opciones.slice(0, 80).map((o) => (
              <label key={o.valor} className="en-env-opcion">
                <input type="checkbox" checked={valores.includes(o.valor)}
                       onChange={(e) => setValores(e.target.checked ? [...valores, o.valor] : valores.filter((v) => v !== o.valor))} />
                {o.texto}
              </label>
            ))}
          </div>
        )}
        {tipo === "docente" && valores.length > 0 && <p className="en-hint">{t.env_elegidos(valores.length)}</p>}

        <label className="en-filters" style={{ display: "grid", marginTop: ".8rem", maxWidth: 420 }}>
          <span>{t.env_correo_prueba}</span>
          <input type="email" className="en-input" value={correoPrueba} onChange={(e) => setCorreoPrueba(e.target.value)} placeholder="nombre@niage.es" />
        </label>
        <p className="en-hint">{t.env_correo_prueba_ayuda}</p>

        <p className="en-botonera">
          <button type="button" className="btn primary" onClick={verDestinatarios}
                  disabled={estado !== "" || (tipo !== "todos" && tipo !== "jefaturas" && valores.length === 0)}>
            {estado === "cargando" ? t.cargando : t.env_ver}
          </button>
        </p>
        {mensaje && <p className={`notice en-alerta${mensaje.ok ? " en-alerta-pos" : " en-alerta-neg"}`} role="status">{mensaje.texto}</p>}
      </div>

      {previa && (
        <div className="card" style={{ marginTop: ".9rem" }}>
          <h3>{t.env_previa}</h3>
          <p className="en-hint">{t.env_previa_lead(listos.length, previa.destinatarios.length - listos.length, previa.dias)}</p>
          <div className="tbl-wrap">
            <table className="doc-table en-tabla-usr">
              <thead><tr><th>{t.env_col_persona}</th><th>{t.env_col_informe}</th><th>{t.env_col_correo}</th><th>{t.env_col_destino}</th><th>{t.env_col_estado}</th></tr></thead>
              <tbody>
                {previa.destinatarios.map((d) => (
                  <tr key={`${d.persona_id}-${d.tipo}-${d.tramo ?? ""}`} className={d.aviso ? "en-env-fuera" : undefined}>
                    <td data-etiqueta={t.env_col_persona}><strong>{d.apellidos}, {d.nombre}</strong>{d.departamento && d.tipo === "profesor" && <><br /><small className="en-hint">{d.departamento}</small></>}</td>
                    <td data-etiqueta={t.env_col_informe}>{textoInforme(d)}</td>
                    <td data-etiqueta={t.env_col_correo}>{d.correo ?? "·"}</td>
                    <td data-etiqueta={t.env_col_destino}>{d.aviso ? "·" : d.destinatario}</td>
                    <td data-etiqueta={t.env_col_estado}>{d.aviso ? t.env_avisos[d.aviso] : t.env_se_envia}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {listos.length > 0 && !confirmando && (
            <p className="en-botonera"><button type="button" className="btn primary" onClick={() => setConfirmando(true)}>✉️ {t.env_enviar(listos.length)}</button></p>
          )}
          {confirmando && (
            <div className="notice en-alerta" role="alertdialog" aria-label={t.env_confirmar_titulo}>
              <p><strong>{t.env_confirmar(listos.length, correoPrueba.trim() || null)}</strong></p>
              <p className="en-botonera">
                <button type="button" className="btn primary" onClick={confirmar} disabled={estado === "enviando"}>
                  {estado === "enviando" ? t.env_enviando : t.env_si_enviar}
                </button>
                <button type="button" className="btn" onClick={() => setConfirmando(false)} disabled={estado === "enviando"}>{t.env_cancelar}</button>
              </p>
            </div>
          )}
        </div>
      )}

      <div className="card" style={{ marginTop: ".9rem" }}>
        <h3>{t.env_enviados}</h3>
        <p className="en-hint">{t.env_enviados_lead}</p>
        {!lista ? <p className="en-cargando">{t.cargando}</p> : lista.length === 0 ? <p className="en-hint">{t.env_ninguno}</p> : (
          <div className="tbl-wrap">
            <table className="doc-table en-tabla-usr">
              <thead><tr><th>{t.env_col_persona}</th><th>{t.env_col_destino}</th><th>{t.env_col_enviado}</th><th>{t.env_col_caduca}</th><th>{t.env_col_aperturas}</th><th /></tr></thead>
              <tbody>{lista.map((e) => <FilaEnviado key={e.id} e={e} alAnular={recargar} />)}</tbody>
            </table>
          </div>
        )}
      </div>
    </>
  );
}

function FilaEnviado({ e, alAnular }: { e: EnlaceEnviado; alAnular: () => void }) {
  const [seguro, setSeguro] = useState(false);
  const caducado = new Date(e.caduca) < new Date();
  return (
    <tr>
      <td data-etiqueta={t.env_col_persona}><strong>{e.docente}</strong>{e.prueba && <> <span className="en-menos5">{t.env_prueba}</span></>}
        <br /><small className="en-hint">{textoInforme({ tipo: e.tipo, tramo: e.tramo, informe: null })}</small></td>
      <td data-etiqueta={t.env_col_destino}>{e.destinatario}</td>
      <td data-etiqueta={t.env_col_enviado}>{e.error ? <span className="en-error">{e.error}</span> : e.enviado ? fechaHora(e.enviado) : e.pendiente ? t.env_pendiente : "·"}</td>
      <td data-etiqueta={t.env_col_caduca}>{e.anulado ? t.env_anulado : `${fechaHora(e.caduca)}${caducado ? ` (${t.env_caducado})` : ""}`}</td>
      <td data-etiqueta={t.env_col_aperturas}>{t.env_aperturas(e.aperturas, e.descargas)}{e.ultima && <><br /><small className="en-hint">{t.env_ultima(fechaHora(e.ultima))}</small></>}</td>
      <td>
        {!e.anulado && !caducado && (seguro
          ? <><button type="button" className="btn" onClick={() => anularEnlace(e.id).then(alAnular)}>{t.env_si_anular}</button>{" "}
              <button type="button" className="btn" onClick={() => setSeguro(false)}>{t.env_cancelar}</button></>
          : <button type="button" className="btn" onClick={() => setSeguro(true)}>{t.env_anular}</button>)}
      </td>
    </tr>
  );
}
