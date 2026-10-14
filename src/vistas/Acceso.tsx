// Acceso con correo y contraseña. Provisional: invitaciones, recuperación de contraseña y
// doble factor llegan en el paso 4.

import { useState, type FormEvent } from "react";
import { entrar } from "../data/sesion";
import { t } from "../i18n";

export function Acceso({ mensaje }: { mensaje?: string | null }) {
  const [correo, setCorreo] = useState("");
  const [contrasena, setContrasena] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    setEnviando(true);
    setError(null);
    try {
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
        <label>{t.correo}
          <input type="email" name="correo" autoComplete="username" required value={correo} onChange={(e) => setCorreo(e.target.value)} />
        </label>
        <label>{t.contrasena}
          <input type="password" name="contrasena" autoComplete="current-password" required value={contrasena} onChange={(e) => setContrasena(e.target.value)} />
        </label>
        {error && <p className="en-error" role="alert">{error}</p>}
        <button className="btn primary" type="submit" disabled={enviando}>{enviando ? t.entrando : t.entrar}</button>
      </form>
    </div>
  );
}
