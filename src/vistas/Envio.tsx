// Envío de informes en un paso (§7.10 y §7.14), en Informes por persona. Solo administración.
//   1. Qué informe: profesorado, jefaturas de departamento, Equipo de Individuación, tutoría o servicios.
//   2. A quién: por defecto, todos sus destinatarios; se puede acotar (departamento, etapa, grupo, servicio…).
//   3. Vista previa: cuántos y quiénes, con avisos separados (sin destinatario, sin correo, sin resultados: se quedan
//      fuera; sin ningún resultado visible en su versión y ya enviado: desmarcados), cada informe tal como lo recibe su
//      destinatario y una casilla para quitar a quien se quiera.
//   4. Confirmar con el número exacto de correos. Abajo, los enlaces enviados con sus aperturas y descargas.
// En modo de pruebas todo va a un correo de prueba: nada al Colegio.

import { useEffect, useMemo, useRef, useState } from "react";
import {
  anularEnlace, enviados, enviar, FILTROS, jefaturas as cargarJefaturas, TIPOS_INFORME, vistaPrevia, visibles,
  type Destinatario, type EnlaceEnviado, type Jefatura, type Seleccion, type TipoFiltro, type TipoInforme, type VistaPrevia,
} from "../data/envio";
import { informeEquipo, informeJefe, informeProfesor, listarProfesores, type Profesor } from "../data/resultados";
import {
  informeServicio, informeTutoria, listarServicios, listarTutorias, type GrupoTutoria, type Servicio,
} from "../data/tutoriaServicios";
import { t } from "../i18n";
import { CuerpoJefatura, CuerpoProfesor } from "./InformeEnlace";
import { CuerpoServicio, CuerpoTutoria } from "./TutoriaServicios";

/** «Informe del profesor/a», «Jefatura de departamento: Ciencias», «Tutoría: Y9 A»… */
export function textoInforme(x: { tipo: TipoInforme; informe?: string | null; tramo: string | null; grupo?: string | null; servicio?: string | null }): string {
  if (x.tipo === "profesor") return t.env_inf_profesor;
  if (x.tipo === "jefatura_departamento") return `${t.env_inf_departamento}${x.informe ? `: ${x.informe}` : ""}`;
  if (x.tipo === "tutoria") return `${t.env_inf_tutoria}: ${x.grupo ?? x.informe ?? ""}`;
  if (x.tipo === "servicio") return `${t.env_inf_servicio}: ${x.servicio ?? x.informe ?? ""}`;
  return `${t.env_inf_equipo}: ${t.env_tramos_todos[(x.tramo ?? x.informe ?? "") as keyof typeof t.env_tramos_todos] ?? x.tramo}`;
}
const ETAPAS = ["primaria", "pai", "bachillerato"];
const TRAMOS_PROFESOR = ["y1_y5", "y6_y9", "y10_y12"];
const TRAMOS_EQUIPO = ["infantil", "y1_y5", "y6_y9", "y10_y12"];
// Únicos destinatarios de prueba (04/11/2026); el servidor y la Edge Function comprueban la misma lista.
const CORREOS_PRUEBA = ["rodrigo@niage.es", "mark.polko@sfpaula.com"] as const;
/** Informes que se comprueban a la vez: el del profesor/a tarda (calcula el informe entero). */
const TANDA: Record<TipoInforme, number> = { profesor: 4, jefatura_departamento: 10, jefatura_equipo: 10, tutoria: 20, servicio: 15 };

const fechaHora = (iso: string) =>
  new Date(iso).toLocaleString("es-ES", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
const fecha = (iso: string) => new Date(iso).toLocaleDateString("es-ES", { day: "2-digit", month: "2-digit", year: "numeric" });
const nombreDe = (d: Destinatario) => (d.persona_id ? `${d.apellidos}, ${d.nombre}` : "·");

export function EnvioInformes() {
  const [profesores, setProfesores] = useState<Profesor[]>([]);
  const [listaJefaturas, setListaJefaturas] = useState<Jefatura[]>([]);
  const [grupos, setGrupos] = useState<GrupoTutoria[]>([]);
  const [servicios, setServicios] = useState<Servicio[]>([]);
  const [informe, setInforme] = useState<TipoInforme>("profesor");
  const [acotar, setAcotar] = useState<TipoFiltro | "todos">("todos");
  const [valores, setValores] = useState<string[]>([]);
  const [busqueda, setBusqueda] = useState("");
  const [correoPrueba, setCorreoPrueba] = useState<string>(CORREOS_PRUEBA[0]);
  const [previa, setPrevia] = useState<VistaPrevia | null>(null);
  const [marcados, setMarcados] = useState<Set<string>>(new Set());
  const [vis, setVis] = useState<Record<string, boolean>>({});
  const [comprobacion, setComprobacion] = useState<{ hechos: number; total: number; error: boolean } | null>(null);
  const [muestra, setMuestra] = useState<Destinatario | null>(null);
  const [confirmando, setConfirmando] = useState(false);
  const [estado, setEstado] = useState<"" | "cargando" | "enviando">("");
  const [mensaje, setMensaje] = useState<{ ok: boolean; texto: string } | null>(null);
  const [lista, setLista] = useState<EnlaceEnviado[] | null>(null);
  // Casillas que ha tocado la persona: la comprobación de lo visible ya no las cambia. Y qué vista previa es la vigente.
  const tocados = useRef<Set<string>>(new Set());
  const vigente = useRef(0);

  const recargar = () => enviados().then(setLista).catch(() => setLista([]));
  useEffect(() => {
    listarProfesores().then(setProfesores).catch(() => {});
    cargarJefaturas().then(setListaJefaturas).catch(() => {});
    listarTutorias().then(setGrupos).catch(() => {});
    listarServicios().then(setServicios).catch(() => {});
    recargar();
  }, []);
  useEffect(() => { setAcotar("todos"); }, [informe]);
  useEffect(() => { setValores([]); setBusqueda(""); }, [acotar, informe]);
  // Cualquier cambio en la selección obliga a ver otra vez los destinatarios antes de enviar.
  useEffect(() => { vigente.current++; setPrevia(null); setConfirmando(false); setMuestra(null); setComprobacion(null); }, [informe, acotar, valores, correoPrueba]);

  const departamentos = useMemo(() => [...new Set(profesores.map((p) => p.departamento).filter(Boolean))]
    .sort((a, b) => a!.localeCompare(b!, "es")) as string[], [profesores]);
  const tutores = useMemo(() => {
    const vistos = new Map<number, string>();
    for (const g of grupos) if (g.tutor) vistos.set(g.tutor.id, `${g.tutor.apellidos}, ${g.tutor.nombre}`);
    return [...vistos].sort((a, b) => a[1].localeCompare(b[1], "es"));
  }, [grupos]);
  const textoTramo = (x: string) => t.env_tramos_todos[x as keyof typeof t.env_tramos_todos] ?? x;
  const opciones: { valor: string; texto: string }[] =
    acotar === "docente" ? profesores.filter((p) => !busqueda || `${p.nombre} ${p.apellidos}`.toLowerCase().includes(busqueda.toLowerCase()))
                             .map((p) => ({ valor: String(p.id), texto: `${p.apellidos}, ${p.nombre}` }))
    : acotar === "departamento" ? departamentos.map((d) => ({ valor: d, texto: d }))
    : acotar === "etapa" ? ETAPAS.map((e) => ({ valor: e, texto: t.etapas[e as keyof typeof t.etapas] }))
    : acotar === "tramo" ? (informe === "jefatura_equipo" ? TRAMOS_EQUIPO : TRAMOS_PROFESOR).map((x) => ({ valor: x, texto: textoTramo(x) }))
    : acotar === "persona" && informe === "tutoria" ? tutores.map(([id, n]) => ({ valor: String(id), texto: n }))
    : acotar === "persona" ? listaJefaturas
        .filter((j) => (informe === "jefatura_departamento" ? j.departamentos.length : j.tramos.length) > 0)
        .map((j) => ({ valor: String(j.id), texto: `${j.apellidos}, ${j.nombre} (${(informe === "jefatura_departamento" ? j.departamentos : j.tramos.map(textoTramo)).join(", ")})` }))
    : acotar === "grupo" ? grupos.map((g) => ({ valor: String(g.id), texto: `${g.nombre}${g.tutor ? ` (${g.tutor.nombre} ${g.tutor.apellidos})` : ` (${t.tut_sin_tutor})`}` }))
    : acotar === "servicio" ? servicios.map((s) => ({ valor: String(s.id), texto: `${s.nombre}${s.responsable ? ` (${s.responsable.nombre} ${s.responsable.apellidos})` : ` (${t.srv_sin_responsable})`}` }))
    : [];
  const seleccion: Seleccion = { informe, filtro: acotar === "todos" ? { tipo: "todos" } : { tipo: acotar, valores } };
  const enviables = previa?.destinatarios.filter((d) => !d.aviso) ?? [];
  const aEnviar = enviables.filter((d) => marcados.has(d.clave));

  async function verDestinatarios() {
    setEstado("cargando"); setMensaje(null); setVis({}); setComprobacion(null); tocados.current = new Set();
    const yo = ++vigente.current;
    try {
      const p = await vistaPrevia(seleccion, correoPrueba.trim());
      if (yo !== vigente.current) return;
      setPrevia(p);
      // Por defecto, todos los que pueden recibirlo menos los que ya lo recibieron.
      setMarcados(new Set(p.destinatarios.filter((d) => !d.aviso && !d.ya_enviado).map((d) => d.clave)));
      comprobar(p.destinatarios.filter((d) => !d.aviso).map((d) => d.clave), yo);
    } catch (e) { setMensaje({ ok: false, texto: (e as Error).message || t.error_datos }); }
    finally { setEstado(""); }
  }

  /** Qué vería cada destinatario en su versión, por tandas: quien no vería nada se desmarca (si no lo ha tocado nadie). */
  async function comprobar(claves: string[], yo: number) {
    if (claves.length === 0) return;
    const tanda = TANDA[informe];
    setComprobacion({ hechos: 0, total: claves.length, error: false });
    for (let i = 0; i < claves.length; i += tanda) {
      let r: Record<string, boolean>;
      try { r = await visibles(claves.slice(i, i + tanda)); }
      catch { if (yo === vigente.current) setComprobacion((c) => c && { ...c, error: true }); return; }
      if (yo !== vigente.current) return;
      setVis((v) => ({ ...v, ...r }));
      setMarcados((m) => {
        const n = new Set(m);
        for (const [k, ok] of Object.entries(r)) if (!ok && !tocados.current.has(k)) n.delete(k);
        return n;
      });
      setComprobacion((c) => c && { ...c, hechos: Math.min(c.total, i + tanda) });
    }
  }

  function marcar(clave: string, si: boolean) {
    tocados.current.add(clave);
    setMarcados((m) => { const n = new Set(m); if (si) n.add(clave); else n.delete(clave); return n; });
    setConfirmando(false);
  }

  async function confirmar() {
    setEstado("enviando"); setMensaje(null);
    try {
      const excluir = enviables.filter((d) => !marcados.has(d.clave)).map((d) => d.clave);
      const r = await enviar(seleccion, correoPrueba.trim(), excluir);
      setMensaje({ ok: r.errores === 0, texto: t.env_resultado(r.enviados, r.errores) });
      setPrevia(null); setConfirmando(false);
      recargar();
    } catch (e) {
      setMensaje({ ok: false, texto: (e as Error).message || t.error_datos });
    } finally { setEstado(""); }
  }

  // Resumen de los avisos, separados.
  const cuenta = (f: (d: Destinatario) => boolean) => previa?.destinatarios.filter(f).length ?? 0;
  const resumen = previa ? ([
    ["sin_destinatario", cuenta((d) => d.aviso === "sin_destinatario")],
    ["sin_correo", cuenta((d) => d.aviso === "sin_correo")],
    ["sin_resultados", cuenta((d) => d.aviso === "sin_resultados")],
    ["sin_visibles", cuenta((d) => !d.aviso && vis[d.clave] === false)],
    ["ya_enviado", cuenta((d) => !d.aviso && !!d.ya_enviado)],
  ] as const).filter(([, n]) => n > 0) : [];

  return (
    <>
      <h2 className="section-title">{t.env_titulo}</h2>
      <p className="sec-lead">{t.env_lead}</p>
      <p className="notice en-alerta">{t.env_pruebas}</p>

      <div className="card">
        <h3>{t.env_que}</h3>
        <div className="chips en-noprint" role="group" aria-label={t.env_que}>
          {TIPOS_INFORME.map((x) => (
            <button key={x} className={`chip${informe === x ? " on" : ""}`} aria-pressed={informe === x} onClick={() => setInforme(x)}>{t.env_informes[x]}</button>
          ))}
        </div>
        <p className="en-hint">{t.env_informe_nota[informe]}</p>
        <h3>{t.env_quien}</h3>
        <div className="chips en-noprint" role="group" aria-label={t.env_quien}>
          <button className={`chip${acotar === "todos" ? " on" : ""}`} aria-pressed={acotar === "todos"} onClick={() => setAcotar("todos")}>{t.env_todos}</button>
          {FILTROS[informe].map((x) => (
            <button key={x} className={`chip${acotar === x ? " on" : ""}`} aria-pressed={acotar === x} onClick={() => setAcotar(x)}>
              {t.env_acotar} {t.env_filtros[x].toLowerCase()}
            </button>
          ))}
        </div>
        {acotar === "docente" && (
          <label className="en-filters" style={{ display: "grid", marginTop: ".6rem" }}>
            <span>{t.prof_buscar}</span>
            <input type="search" className="en-input" value={busqueda} onChange={(e) => setBusqueda(e.target.value)} placeholder={t.prof_buscar_ph} />
          </label>
        )}
        {acotar !== "todos" && (
          <>
            <div className="en-env-opciones">
              {opciones.slice(0, 120).map((o) => (
                <label key={o.valor} className="en-env-opcion">
                  <input type="checkbox" checked={valores.includes(o.valor)}
                         onChange={(e) => setValores(e.target.checked ? [...valores, o.valor] : valores.filter((v) => v !== o.valor))} />
                  {o.texto}
                </label>
              ))}
            </div>
            <p className="en-hint">{valores.length ? t.env_elegidos(valores.length) : t.env_elegir}</p>
          </>
        )}

        <label className="en-filters" style={{ display: "grid", marginTop: ".8rem", maxWidth: 420 }}>
          <span>{t.env_correo_prueba}</span>
          <select value={correoPrueba} onChange={(e) => setCorreoPrueba(e.target.value)}>
            {CORREOS_PRUEBA.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        </label>
        <p className="en-hint">{t.env_correo_prueba_ayuda}</p>

        <p className="en-botonera">
          <button type="button" className="btn primary" onClick={verDestinatarios}
                  disabled={estado !== "" || (acotar !== "todos" && valores.length === 0)}>
            {estado === "cargando" ? t.cargando : t.env_ver}
          </button>
        </p>
        {mensaje && <p className={`notice en-alerta${mensaje.ok ? " en-alerta-pos" : " en-alerta-neg"}`} role="status">{mensaje.texto}</p>}
      </div>

      {previa && (
        <div className="card" style={{ marginTop: ".9rem" }}>
          <h3>{t.env_previa}</h3>
          <p className="en-hint">{t.env_previa_lead(aEnviar.length, previa.destinatarios.length, previa.dias)}</p>
          {comprobacion && (
            <p className="en-hint" role="status">
              {comprobacion.error ? t.env_comprobar_error
                : comprobacion.hechos < comprobacion.total ? t.env_comprobando(comprobacion.hechos, comprobacion.total) : t.env_comprobado}
            </p>
          )}
          {resumen.length > 0 && (
            <div className="notice en-alerta">
              <p><strong>{t.env_avisos_titulo}</strong></p>
              <ul className="en-notas-tabla">{resumen.map(([k, n]) => <li key={k}>{t.env_resumen_avisos[k](n)}</li>)}</ul>
            </div>
          )}
          <div className="tbl-wrap">
            <table className="doc-table en-tabla-usr">
              <thead><tr><th>{t.env_col_enviar}</th><th>{t.env_col_persona}</th><th>{t.env_col_informe}</th><th>{t.env_col_destino}</th><th>{t.env_col_estado}</th><th /></tr></thead>
              <tbody>
                {previa.destinatarios.map((d) => (
                  <tr key={d.clave} className={d.aviso || !marcados.has(d.clave) ? "en-env-fuera" : undefined}>
                    <td data-etiqueta={t.env_col_enviar}>
                      {d.aviso ? "·" : <input type="checkbox" checked={marcados.has(d.clave)} aria-label={t.env_incluir(`${nombreDe(d)} · ${textoInforme(d)}`)}
                                              onChange={(e) => marcar(d.clave, e.target.checked)} />}
                    </td>
                    <td data-etiqueta={t.env_col_persona}><strong>{nombreDe(d)}</strong>
                      {d.persona_id && d.departamento && d.tipo === "profesor" && <><br /><small className="en-hint">{d.departamento}</small></>}
                      {d.correo && <><br /><small className="en-hint">{d.correo}</small></>}</td>
                    <td data-etiqueta={t.env_col_informe}>{textoInforme(d)}</td>
                    <td data-etiqueta={t.env_col_destino}>{d.aviso ? "·" : d.destinatario}</td>
                    <td data-etiqueta={t.env_col_estado}>{estadoDe(d, vis[d.clave], marcados.has(d.clave))}</td>
                    <td>{!d.aviso && <button type="button" className="btn" onClick={() => setMuestra(d)}>{t.env_ver_muestra}</button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {aEnviar.length > 0 && !confirmando && (
            <p className="en-botonera"><button type="button" className="btn primary" onClick={() => setConfirmando(true)}>✉️ {t.env_enviar(aEnviar.length)}</button></p>
          )}
          {confirmando && (
            <div className="notice en-alerta" role="alertdialog" aria-label={t.env_confirmar_titulo}>
              <p><strong>{t.env_confirmar(aEnviar.length, correoPrueba.trim() || null)}</strong></p>
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

      {muestra && <Muestra d={muestra} alCerrar={() => setMuestra(null)} />}

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

function estadoDe(d: Destinatario, visible: boolean | undefined, marcado: boolean): string {
  if (d.aviso === "sin_destinatario") return t.env_sin_destinatario[d.tipo] ?? t.env_avisos.sin_destinatario;
  if (d.aviso === "sin_resultados") return t.env_sin_resultados[d.tipo] ?? t.env_avisos.sin_resultados;
  if (d.aviso) return t.env_avisos[d.aviso];
  const notas = [
    ...(visible === false ? [t.env_sin_visibles] : []),
    ...(d.ya_enviado ? [t.env_ya_enviado(fecha(d.ya_enviado))] : []),
  ];
  return [marcado ? t.env_se_envia : t.env_no_se_envia, ...notas].join(" · ");
}

/** El informe tal como lo recibe su destinatario (con el mínimo de 5), para comprobarlo antes de enviar. */
function Muestra({ d, alCerrar }: { d: Destinatario; alCerrar: () => void }) {
  const [cuerpo, setCuerpo] = useState<JSX.Element | null>(null);
  const [error, setError] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    let vale = true;
    setCuerpo(null); setError(false);
    const pedir = async (): Promise<JSX.Element> => {
      switch (d.tipo) {
        case "profesor": return <CuerpoProfesor informe={await informeProfesor(d.persona_id!, false, "docente")} />;
        case "jefatura_departamento": return <CuerpoJefatura dep={await informeJefe(d.persona_id!, false, "jefatura")} eq={null} />;
        case "jefatura_equipo": return <CuerpoJefatura dep={null} eq={await informeEquipo([d.tramo!], false, "jefatura")} />;
        case "tutoria": return <CuerpoTutoria inf={await informeTutoria(d.grupo_id!, false, "tutor")} />;
        case "servicio": return <CuerpoServicio inf={await informeServicio(d.servicio_id!, false, "responsable")} />;
      }
    };
    pedir().then((c) => vale && setCuerpo(c)).catch(() => vale && setError(true));
    ref.current?.scrollIntoView({ behavior: "smooth", block: "start" });
    return () => { vale = false; };
  }, [d]);
  return (
    <div ref={ref} className="card en-muestra" style={{ marginTop: ".9rem" }} role="region" aria-label={t.env_muestra_titulo(textoInforme(d))}>
      <p className="en-botonera" style={{ justifyContent: "space-between" }}>
        <strong>{t.env_muestra_titulo(`${d.persona_id ? `${d.nombre} ${d.apellidos} · ` : ""}${textoInforme(d)}`)}</strong>
        <button type="button" className="btn" onClick={alCerrar}>{t.env_cerrar}</button>
      </p>
      <p className="en-version">{t.env_muestra_nota}</p>
      {error ? <p className="notice en-alerta en-alerta-neg" role="alert">{t.error_datos}</p> : cuerpo ?? <p className="en-cargando">{t.cargando}</p>}
    </div>
  );
}

function FilaEnviado({ e, alAnular }: { e: EnlaceEnviado; alAnular: () => void }) {
  const [seguro, setSeguro] = useState(false);
  const caducado = new Date(e.caduca) < new Date();
  return (
    <tr>
      <td data-etiqueta={t.env_col_persona}><strong>{e.docente}</strong>{e.prueba && <> <span className="en-menos5">{t.env_prueba}</span></>}
        <br /><small className="en-hint">{textoInforme({ tipo: e.tipo, tramo: e.tramo, grupo: e.grupo, servicio: e.servicio })}</small></td>
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
