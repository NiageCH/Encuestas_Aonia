// Estructura de página de la intranet (§8): skip link, header.topbar, main#app,
// footer.footer y #toast, en este orden.

import { useState, type ReactNode } from "react";
import logo from "../recursos/logo.webp";
import logoBlanco from "../recursos/logo-blanco.webp";
import { t } from "../i18n";

export interface Enlace {
  ruta: string;
  texto: string;
  pronto?: boolean;
}

interface Props {
  ruta: string;
  enlaces: Enlace[];
  usuario?: { nombre: string; onSalir: () => void };
  aviso?: string | null;
  children: ReactNode;
}

export function Marco({ ruta, enlaces, usuario, aviso, children }: Props) {
  const [menu, setMenu] = useState(false);
  return (
    <>
      <a className="skip" href="#app">{t.skip}</a>
      <header className="topbar">
        <a className="brand" href="#/">
          <img className="brand-logo" src={logo} alt="Colegio Internacional de Sevilla – San Francisco de Paula" width={126} height={44} />
          <span className="brand-text"><strong>{t.brand_title}</strong><small>{t.brand_sub}</small></span>
        </a>
        {enlaces.length > 0 && (
          <nav className={`topnav${menu ? " open" : ""}`} id="topnav" aria-label={t.menu}>
            {enlaces.map((e) => (
              <a key={e.ruta} href={`#${e.ruta}`} className={ruta === e.ruta ? "on" : undefined}
                 aria-current={ruta === e.ruta ? "page" : undefined} onClick={() => setMenu(false)}>
                {e.texto}
              </a>
            ))}
          </nav>
        )}
        <div className="top-actions">
          {usuario && (
            <div className="en-usuario">
              <span><strong>{usuario.nombre}</strong></span>
              <button className="btn" type="button" onClick={usuario.onSalir}>{t.salir}</button>
            </div>
          )}
          {enlaces.length > 0 && (
            <button className="menu-btn" type="button" aria-label={t.menu} aria-expanded={menu} aria-controls="topnav"
                    onClick={() => setMenu(!menu)}>☰</button>
          )}
        </div>
      </header>

      <main id="app" tabIndex={-1}>{children}</main>

      <footer className="footer">
        <div className="f-main">
          <a className="f-logo" href="https://colegiosfpaula.com/" target="_blank" rel="noopener">
            <img src={logoBlanco} alt="Colegio Internacional de Sevilla – San Francisco de Paula" width={200} height={70} />
          </a>
          <div className="f-course"><strong>{t.brand_title}</strong><span>{t.f_sub}</span></div>
          <div className="f-links">
            <a href="https://colegiosfpaula.com/" target="_blank" rel="noopener">{t.f_school} ↗</a>
            <a href="https://intranet-cis-sfp.vibetasking.site/" target="_blank" rel="noopener">{t.f_intranet} ↗</a>
            <span>{t.f_note}</span>
          </div>
        </div>
      </footer>

      <div id="toast" className="toast" hidden={!aviso} role="status" aria-live="polite">{aviso}</div>
    </>
  );
}

export function Migas({ actual }: { actual: string }) {
  return (
    <nav className="crumbs" aria-label="breadcrumb">
      <a href="https://intranet-cis-sfp.vibetasking.site/" target="_blank" rel="noopener">{t.crumb_intranet}</a>
      <span className="sep">›</span><span>{t.crumb_tools}</span>
      <span className="sep">›</span><span>{t.brand_title}</span>
      <span className="sep">›</span><span>{actual}</span>
    </nav>
  );
}
