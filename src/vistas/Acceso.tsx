// Acceso con correo y contraseña (alta solo por invitación) y petición de enlace para
// recuperar la contraseña (§7.5).

import { useState, type FormEvent } from "react";
import { entrar, pedirRecuperacion } from "../data/sesion";
import { t } from "../i18n";

export function Acceso({ mensaje }: { mensaje?: string | null }) {
  const [correo, setCorreo] = useState("");
  const [contrasena, setContrasena] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [recuperar, setRecuperar] = useState(false);
  const [enviado, setEnviado] = useState(false);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    setEnviando(true);
    setError(null);
    try {
      if (recuperar) {
        await pedirRecuperacion(correo.trim());
        setEnviado(true);
        return;
      }
      await entrar(correo.trim(), contrasena);
    } catch {
      setError(t.error_acceso);
    } finally {
      setEnviando(false);
    }
  }

  return (
    <div className="page narrow">
      <p className="eyebrow">{t.acceso_eyebrow}</p>
      <h1>🔐 {t.acceso_titulo}</h1>
      <p className="lead">{t.acceso_lead}</p>
      {mensaje && <p className="notice">{mensaje}</p>}
      <form className="card en-form" onSubmit={enviar}>
        {recuperar && <p className="en-hint" style={{ margin: 0 }}>{t.recuperar_lead}</p>}
        <label>{t.correo}
          <input type="email" name="correo" autoComplete="username" required value={correo} onChange={(e) => setCorreo(e.target.value)} />
        </label>
        {!recuperar && (
          <label>{t.contrasena}
            <input type="password" name="contrasena" autoComplete="current-password" required value={contrasena} onChange={(e) => setContrasena(e.target.value)} />
          </label>
        )}
        {error && <p className="en-error" role="alert">{error}</p>}
        {enviado && <p className="notice" role="status" style={{ margin: 0 }}>{t.recuperar_enviado}</p>}
        <button className="btn primary" type="submit" disabled={enviando || enviado}>
          {recuperar ? t.recuperar_boton : enviando ? t.entrando : t.entrar}
        </button>
        <button type="button" className="en-enlace" onClick={() => { setRecuperar(!recuperar); setEnviado(false); setError(null); }}>
          {recuperar ? t.recuperar_volver : t.recuperar_enlace}
        </button>
      </form>
    </div>
  );
}
