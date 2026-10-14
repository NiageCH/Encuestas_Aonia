// Contraseña nueva al aceptar la invitación o al recuperar la contraseña (§7.5).

import { useState, type FormEvent } from "react";
import { cambiarContrasena } from "../data/sesion";
import { t } from "../i18n";

export function NuevaContrasena({ invitacion, alTerminar }: { invitacion: boolean; alTerminar: () => void }) {
  const [clave, setClave] = useState("");
  const [repetida, setRepetida] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    setError(null);
    // Mismas reglas que Auth (config.toml): 10 caracteres como mínimo, con letras y números.
    if (clave.length < 10 || !/[A-Za-z]/.test(clave) || !/\d/.test(clave)) { setError(t.clave_reglas); return; }
    if (clave !== repetida) { setError(t.clave_distintas); return; }
    setEnviando(true);
    try {
      await cambiarContrasena(clave);
      alTerminar();
    } catch {
      setError(t.clave_error);
    } finally {
      setEnviando(false);
    }
  }

  return (
    <div className="page narrow">
      <p className="eyebrow">{t.acceso_eyebrow}</p>
      <h1>🔑 {invitacion ? t.clave_titulo_invitacion : t.clave_titulo_recuperacion}</h1>
      <p className="lead">{invitacion ? t.clave_lead_invitacion : t.clave_lead_recuperacion}</p>
      <form className="card en-form" onSubmit={enviar}>
        <label>{t.clave_nueva}
          <input type="password" autoComplete="new-password" required value={clave} onChange={(e) => setClave(e.target.value)} aria-describedby="reglas-clave" />
        </label>
        <p id="reglas-clave" className="en-hint" style={{ margin: 0 }}>{t.clave_reglas}</p>
        <label>{t.clave_repetir}
          <input type="password" autoComplete="new-password" required value={repetida} onChange={(e) => setRepetida(e.target.value)} />
        </label>
        {error && <p className="en-error" role="alert">{error}</p>}
        <button className="btn primary" type="submit" disabled={enviando}>{t.clave_guardar}</button>
      </form>
    </div>
  );
}
