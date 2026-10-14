// Usuarios y registro de actividad (§7.5, mockup 5; estilo de la intranet). Solo
// administradores: el servidor lo comprueba en cada RPC y en la Edge Function.

import { useEffect, useState, type FormEvent } from "react";
import { Migas } from "../componentes/Marco";
import {
  actualizarUsuario, invitar, reenviarInvitacion, registro as cargarRegistro, usuarios as cargarUsuarios,
  type EntradaRegistro, type Usuario,
} from "../data/admin";
import type { Perfil, Rol } from "../data/sesion";
import { t } from "../i18n";

const ROLES: Rol[] = ["administrador", "direccion", "coordinacion"];
const ETAPAS = ["infantil", "primaria", "pai", "bachillerato"] as const;

export function Usuarios({ perfil }: { perfil: Perfil }) {
  const [lista, setLista] = useState<Usuario[] | null>(null);
  const [actividad, setActividad] = useState<EntradaRegistro[] | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function recargar() {
    try {
      const [u, r] = await Promise.all([cargarUsuarios(), cargarRegistro(100)]);
      setLista(u);
      setActividad(r);
    } catch {
      setError(t.error_datos);
    }
  }
  useEffect(() => { recargar(); }, []);

  async function accion(fn: () => Promise<void>, ok: string) {
    setAviso(null);
    setError(null);
    try {
      await fn();
      setAviso(ok);
      await recargar();
    } catch (e) {
      setError((e as Error).message || t.error_datos);
    }
  }

  const activos = lista?.filter((u) => u.estado === "activo").length ?? 0;
  const pendientes = lista?.filter((u) => u.estado === "pendiente").length ?? 0;
  const sinAcceso = lista?.filter((u) => u.aviso_90_dias).length ?? 0;
  const admins = lista?.filter((u) => u.rol === "administrador" && u.estado !== "desactivado") ?? [];

  return (
    <div className="page">
      <Migas actual={t.nav_usuarios} />
      <p className="eyebrow">{t.usr_eyebrow}</p>
      <h1>👥 {t.usr_titulo}</h1>
      <p className="lead">{t.usr_lead}</p>
      {aviso && <p className="notice" role="status">{aviso}</p>}
      {error && <p className="notice en-error" role="alert">{error}</p>}
      {!lista && !error && <p className="en-cargando">{t.cargando}</p>}
      {lista && (
        <>
          <div className="en-kpis">
            <div className="card en-kpi hl"><div className="l">{t.usr_k_activos}</div><div className="v">{activos}</div><div className="d">{t.usr_k_activos_d(lista.length)}</div></div>
            <div className="card en-kpi"><div className="l">{t.usr_k_pendientes}</div><div className="v">{pendientes}</div><div className="d">{t.usr_k_pendientes_d}</div></div>
            <div className="card en-kpi"><div className="l">{t.usr_k_90}</div><div className="v">{sinAcceso}</div><div className="d">{t.usr_k_90_d}</div></div>
            <div className="card en-kpi"><div className="l">{t.usr_k_mfa}</div><div className="v">{admins.filter((a) => a.doble_factor).length} <small>{t.usr_de(admins.length)}</small></div><div className="d">{t.usr_k_mfa_d}</div></div>
          </div>

          <div className="en-usr">
            <section>
              <h2 className="section-title">{t.usr_equipo}</h2>
              <p className="sec-lead">{t.usr_equipo_lead}</p>
              <div className="tbl-wrap">
                <table className="doc-table en-tabla-usr">
                  <thead><tr><th>{t.usr_persona}</th><th>{t.usr_rol}</th><th>{t.usr_estado}</th><th>{t.usr_ultimo}</th><th>{t.usr_mfa}</th><th><span className="en-sr">{t.usr_acciones}</span></th></tr></thead>
                  <tbody>
                    {lista.map((u) => <FilaUsuario key={u.id} u={u} yo={u.id === perfil.id} accion={accion} />)}
                  </tbody>
                </table>
              </div>
            </section>
            <aside>
              <Invitar accion={accion} />
            </aside>
          </div>

          <h2 className="section-title">{t.usr_registro}</h2>
          <p className="sec-lead">{t.usr_registro_lead}</p>
          <div className="card">
            {actividad && actividad.length === 0 && <p className="en-hint">{t.usr_registro_vacio}</p>}
            <ul className="en-registro">
              {actividad?.map((e, i) => (
                <li key={i}><time dateTime={e.fecha}>{fechaHora(e.fecha)}</time><span>{describir(e)}</span></li>
              ))}
            </ul>
          </div>
        </>
      )}
    </div>
  );
}

function FilaUsuario({ u, yo, accion }: { u: Usuario; yo: boolean; accion: (fn: () => Promise<void>, ok: string) => Promise<void> }) {
  const [editando, setEditando] = useState(false);
  const [rol, setRol] = useState<Rol>(u.rol);
  const [etapa, setEtapa] = useState<string | null>(u.etapa);
  const [confirmar, setConfirmar] = useState(false);

  return (
    <tr className={u.aviso_90_dias ? "en-aviso-fila" : undefined}>
      <td><strong>{u.nombre}</strong>{yo && <small> · {t.usr_tu}</small>}<br /><small className="en-hint">{u.correo}</small></td>
      <td>
        {editando ? (
          <span className="en-edicion">
            <span className="en-select"><select aria-label={t.usr_rol} value={rol} onChange={(e) => { const r = e.target.value as Rol; setRol(r); setEtapa(r === "coordinacion" ? etapa ?? "primaria" : null); }}>
              {ROLES.map((r) => <option key={r} value={r}>{t.roles[r]}</option>)}
            </select></span>
            {rol === "coordinacion" && (
              <span className="en-select"><select aria-label={t.etapa} value={etapa ?? "primaria"} onChange={(e) => setEtapa(e.target.value)}>
                {ETAPAS.map((x) => <option key={x} value={x}>{t.etapas[x]}</option>)}
              </select></span>
            )}
          </span>
        ) : (
          <><span className={`en-rol en-rol-${u.rol}`}>{t.roles[u.rol]}</span>{u.etapa && <small> · {t.etapas[u.etapa as keyof typeof t.etapas]}</small>}</>
        )}
      </td>
      <td><span className={`en-estado en-estado-${u.estado}`}>{u.aviso_90_dias ? t.usr_sin_acceso_90 : t.usr_estados[u.estado]}</span></td>
      <td>{u.ultimo_acceso ? fechaCorta(u.ultimo_acceso) : <small className="en-hint">{t.usr_invitado(fechaCorta(u.invitado))}</small>}</td>
      <td>{u.rol === "administrador" ? (u.doble_factor ? t.usr_mfa_si : t.usr_mfa_no) : "·"}</td>
      <td className="en-acciones">
        {editando ? (
          <>
            <button type="button" className="btn primary" onClick={async () => {
              await accion(() => actualizarUsuario(u.id, rol, rol === "coordinacion" ? etapa : null, u.estado !== "desactivado"), t.usr_ok_cambio);
              setEditando(false);
            }}>{t.usr_guardar}</button>
            <button type="button" className="btn" onClick={() => { setEditando(false); setRol(u.rol); setEtapa(u.etapa); }}>{t.usr_cancelar}</button>
          </>
        ) : confirmar ? (
          <>
            <button type="button" className="btn primary" onClick={async () => {
              await accion(() => actualizarUsuario(u.id, u.rol, u.etapa, u.estado === "desactivado"),
                u.estado === "desactivado" ? t.usr_ok_reactivado : t.usr_ok_desactivado);
              setConfirmar(false);
            }}>{u.estado === "desactivado" ? t.usr_confirmar_reactivar : t.usr_confirmar_desactivar}</button>
            <button type="button" className="btn" onClick={() => setConfirmar(false)}>{t.usr_cancelar}</button>
          </>
        ) : (
          <>
            {!yo && <button type="button" className="btn" onClick={() => setEditando(true)}>{t.usr_editar}</button>}
            {u.estado === "pendiente" && (
              <button type="button" className="btn" onClick={() => accion(() => reenviarInvitacion(u.id), t.usr_ok_reenviada)}>{t.usr_reenviar}</button>
            )}
            {!yo && <button type="button" className="btn" onClick={() => setConfirmar(true)}>{u.estado === "desactivado" ? t.usr_reactivar : t.usr_desactivar}</button>}
          </>
        )}
      </td>
    </tr>
  );
}

function Invitar({ accion }: { accion: (fn: () => Promise<void>, ok: string) => Promise<void> }) {
  const [nombre, setNombre] = useState("");
  const [correo, setCorreo] = useState("");
  const [rol, setRol] = useState<Rol>("direccion");
  const [etapa, setEtapa] = useState("primaria");
  const [enviando, setEnviando] = useState(false);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    setEnviando(true);
    await accion(() => invitar(nombre.trim(), correo.trim(), rol, rol === "coordinacion" ? etapa : null), t.usr_ok_invitado(correo.trim()));
    setEnviando(false);
    setNombre(""); setCorreo("");
  }

  return (
    <form className="card en-form en-invitar" onSubmit={enviar}>
      <p className="eyebrow">{t.usr_nuevo}</p>
      <h3 style={{ margin: 0 }}>{t.usr_invitar}</h3>
      <p className="en-hint" style={{ margin: 0 }}>{t.usr_invitar_lead}</p>
      <label>{t.usr_nombre}<input required value={nombre} onChange={(e) => setNombre(e.target.value)} autoComplete="off" /></label>
      <label>{t.correo}<input type="email" required value={correo} onChange={(e) => setCorreo(e.target.value)} autoComplete="off" /></label>
      <fieldset className="en-roles">
        <legend>{t.usr_rol}</legend>
        {ROLES.map((r) => (
          <label key={r} className={`en-opcion${rol === r ? " on" : ""}`}>
            <input type="radio" name="rol" value={r} checked={rol === r} onChange={() => setRol(r)} />
            <span><strong>{t.roles[r]}</strong><small>{t.roles_d[r]}</small></span>
          </label>
        ))}
      </fieldset>
      {rol === "coordinacion" && (
        <label>{t.etapa}
          <span className="en-select"><select value={etapa} onChange={(e) => setEtapa(e.target.value)}>
            {ETAPAS.map((x) => <option key={x} value={x}>{t.etapas[x]}</option>)}
          </select></span>
        </label>
      )}
      <button className="btn primary" type="submit" disabled={enviando}>{t.usr_enviar}</button>
      <p className="notice" style={{ margin: 0 }}>{t.usr_caducidad}</p>
    </form>
  );
}

function fechaCorta(iso: string) {
  return new Date(iso).toLocaleDateString("es-ES", { day: "numeric", month: "short", year: "numeric" });
}
function fechaHora(iso: string) {
  return new Date(iso).toLocaleString("es-ES", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
}

function describir(e: EntradaRegistro): string {
  const d = e.detalle as Record<string, string | boolean | null | Record<string, string>>;
  const quien = String(d.nombre ?? "");
  switch (e.accion) {
    case "invitacion": return t.reg_invitacion(e.usuario, quien, t.roles[d.rol as Rol] ?? String(d.rol));
    case "reenvio_invitacion": return t.reg_reenvio(e.usuario, quien);
    case "desactivacion": return t.reg_desactivacion(e.usuario, quien);
    case "reactivacion": return t.reg_reactivacion(e.usuario, quien);
    case "cambio_rol": {
      const despues = d.despues as Record<string, string>;
      return t.reg_cambio_rol(e.usuario, quien, t.roles[despues.rol as Rol] ?? despues.rol);
    }
    case "informe_profesor": return d.lote ? t.reg_informe_lote(e.usuario) : t.reg_informe_profesor(e.usuario);
    case "informe_responsable": return t.reg_informe_responsable(e.usuario, String(d.ambito ?? d.tipo ?? ""));
    default: return `${e.usuario}: ${e.accion}`;
  }
}
