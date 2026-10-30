// Navegar al detalle (30/10/2026): la ruta y el rol para las vistas, los cambios de filtro en la dirección, la banda
// «Detalle» con «Volver» y «Quitar el filtro», y bajar al apartado pedido cuando ya hay datos.

import { createContext, useCallback, useContext, useEffect, useRef, type ReactNode } from "react";
import { conCambios, destino as destinoPuro, soloFiltros } from "../detalle";
import { t } from "../i18n";
import { aHash, type Rol, type Ruta } from "../navegacion";

interface Navegacion { ruta: Ruta; rol: Rol }

const Contexto = createContext<Navegacion>({ ruta: { seccion: "/" }, rol: "coordinacion" });

export function ProveedorNavegacion({ ruta, rol, children }: Navegacion & { children: ReactNode }) {
  return <Contexto.Provider value={{ ruta, rol }}>{children}</Contexto.Provider>;
}

/** Cambia la dirección sin añadir un paso al historial (filtros de la propia pantalla). */
function reemplazar(hash: string) {
  if (hash === window.location.hash) return;
  window.history.replaceState(null, "", hash);
  window.dispatchEvent(new HashChangeEvent("hashchange"));
}

export function useNavegacion() {
  const { ruta, rol } = useContext(Contexto);
  const filtro = ruta.filtro ?? {};
  /** Cambia filtros de esta pantalla. Se queda «volver» (la banda muestra los filtros que haya en cada momento); se
   *  quitan el apartado al que bajar y lo resaltado. */
  const cambiar = useCallback((cambios: Record<string, string | null | undefined>) => {
    const base = { ...soloFiltros(filtro), ...(filtro.volver ? { volver: filtro.volver } : {}) };
    reemplazar(aHash({ ...ruta, filtro: conCambios(base, cambios) }));
  }, [ruta, filtro]);
  /** Dirección de detalle en otra pantalla (o en esta), o nada si el rol no la puede ver. */
  const destino = useCallback((r: Ruta) => destinoPuro(r, rol, window.location.hash), [rol]);
  /** Detalle en esta misma pantalla: los filtros actuales más los cambios. */
  const aqui = useCallback((cambios: Record<string, string | null | undefined>) =>
    destinoPuro({ ...ruta, filtro: conCambios(soloFiltros(filtro), cambios) }, rol, window.location.hash), [ruta, filtro, rol]);
  return { ruta, rol, filtro, cambiar, destino, aqui };
}

/** Banda de la pantalla de destino: qué filtro se aplicó, «Volver» y «Quitar el filtro». Solo al llegar pulsando. */
export function BandaDetalle({ partes, quitar }: { partes: [string, string][]; quitar?: Record<string, null> }) {
  // Sin «quitar»: la pantalla sin ningún filtro de la dirección.
  const { ruta, filtro } = useNavegacion();
  const ref = useRef<HTMLDivElement>(null);
  const volver = filtro.volver;
  useEffect(() => { if (volver && !filtro.ver) ref.current?.focus(); }, [volver, filtro.ver]);
  if (!volver) return null;
  const sinFiltro = quitar ? conCambios(soloFiltros(filtro), quitar) : {};
  return (
    <div ref={ref} tabIndex={-1} className="en-banda-detalle en-noprint" role="region" aria-label={t.det_banda}>
      <span className="en-banda-t">{t.det_banda}:</span>
      {partes.map(([k, v]) => <span key={k} className="en-banda-filtro"><small>{k}</small> {v}</span>)}
      <span className="en-banda-acciones">
        <a className="btn" href={volver}>← {t.det_volver}</a>
        <a className="btn" href={aHash({ ...ruta, filtro: sinFiltro })}>✕ {t.det_quitar}</a>
      </span>
    </div>
  );
}

/** Baja al apartado «ver» de la dirección (y le pasa el foco) en cuanto la pantalla tiene sus datos. Una vez por
 *  dirección: los cambios posteriores de la propia pantalla no vuelven a mover la página. */
export function useBajarA(listo: boolean) {
  const { filtro } = useNavegacion();
  const hecho = useRef("");
  useEffect(() => {
    const id = filtro.pregunta ? `en-pregunta-${filtro.pregunta}` : filtro.clase ? `en-clase-${filtro.clase}` : filtro.ver;
    if (!listo || !id || !filtro.volver || hecho.current === window.location.hash) return;
    const el = document.getElementById(id) ?? (filtro.ver ? document.getElementById(filtro.ver) : null);
    if (!el) return;
    hecho.current = window.location.hash;
    el.scrollIntoView({ block: "start" });
    window.scrollBy(0, -90);   // por debajo de la cabecera fija
    if (!el.hasAttribute("tabindex")) el.setAttribute("tabindex", "-1");
    el.focus({ preventScroll: true });
  });
}
