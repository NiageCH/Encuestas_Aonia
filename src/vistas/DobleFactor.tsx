// Doble factor obligatorio para administradores (§3): alta con QR la primera vez y código de
// la aplicación de autenticación en cada inicio de sesión.

import { useEffect, useState, type FormEvent } from "react";
import { altaTotp, factoresTotp, verificarTotp } from "../data/sesion";
import { t } from "../i18n";

export function DobleFactor({ alSalir }: { alSalir: () => void }) {
  const [factor, setFactor] = useState<string | null>(null);
  const [alta, setAlta] = useState<{ qr: string; secreto: string } | null>(null);
  const [codigo, setCodigo] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  useEffect(() => {
    (async () => {
      const verificado = (await factoresTotp()).find((f) => f.verificado);
      if (verificado) { setFactor(verificado.id); return; }
      const nuevo = await altaTotp();
      setFactor(nuevo.id);
      setAlta({ qr: nuevo.qr, secreto: nuevo.secreto });
    })().catch(() => setError(t.mfa_error_carga));
  }, []);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    if (!factor) return;
    setEnviando(true);
    setError(null);
    try {
      await verificarTotp(factor, codigo);   // la sesión pasa a aal2 y la aplicación se abre sola
    } catch {
      setError(t.mfa_codigo_incorrecto);
    } finally {
      setEnviando(false);
    }
  }

  return (
    <div className="page narrow">
      <p className="eyebrow">{t.acceso_eyebrow}</p>
      <h1>🛡️ {t.mfa_titulo}</h1>
      <p className="lead">{alta ? t.mfa_lead_alta : t.mfa_lead}</p>
      {error && <p className="en-error" role="alert">{error}</p>}
      <form className="card en-form" onSubmit={enviar}>
        {alta && (
          <div className="en-mfa-alta">
            <img src={alta.qr} alt={t.mfa_qr_alt} width={180} height={180} />
            <p className="en-hint" style={{ margin: 0 }}>{t.mfa_secreto}</p>
            <code className="en-secreto">{alta.secreto}</code>
          </div>
        )}
        <label>{t.mfa_codigo}
          <input inputMode="numeric" autoComplete="one-time-code" pattern="[0-9 ]{6,7}" required value={codigo}
                 onChange={(e) => setCodigo(e.target.value)} />
        </label>
        <button className="btn primary" type="submit" disabled={enviando || !factor}>{t.mfa_verificar}</button>
        <button type="button" className="en-enlace" onClick={alSalir}>{t.salir}</button>
      </form>
    </div>
  );
}
