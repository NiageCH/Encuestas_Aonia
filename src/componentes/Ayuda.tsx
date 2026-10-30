// Información emergente de los gráficos: aparece al pasar el ratón y también al llegar con
// el teclado (el elemento recibe el foco y lleva el mismo texto en aria-label).
//
// Con destino (navegar al detalle, 30/10/2026): la tarjeta acaba en «Pulsa para ver el detalle»; un clic o Intro (o la
// barra espaciadora) abre el detalle. En pantalla táctil, la primera pulsación muestra la tarjeta con el enlace «Ver el
// detalle» y la siguiente fuera la cierra.

import {
  createContext, useCallback, useContext, useEffect, useRef, useState,
  type FocusEvent, type KeyboardEvent, type MouseEvent, type PointerEvent, type ReactNode,
} from "react";
import { t } from "../i18n";

interface Estado { lineas: string[]; x: number; y: number; destino?: string; tactil?: boolean; origen?: EventTarget }

// Valor estable (el setter y una referencia al estado): pasar el ratón no vuelve a pintar los gráficos.
interface Valor { setEstado: (e: Estado | null) => void; actual: { current: Estado | null } }
const Contexto = createContext<Valor>({ setEstado: () => {}, actual: { current: null } });

export function ProveedorAyuda({ children }: { children: ReactNode }) {
  const [estado, setEstado] = useState<Estado | null>(null);
  const actual = useRef<Estado | null>(null);
  actual.current = estado;
  const valor = useRef<Valor>({ setEstado, actual }).current;
  const tip = useRef<HTMLDivElement>(null);
  // Tarjeta táctil abierta: se cierra al pulsar fuera de ella y de su elemento.
  useEffect(() => {
    if (!estado?.tactil) return;
    const fuera = (e: Event) => {
      const n = e.target as Node;
      if (tip.current?.contains(n) || (estado.origen as Node | undefined)?.contains?.(n)) return;
      setEstado(null);
    };
    document.addEventListener("pointerdown", fuera);
    return () => document.removeEventListener("pointerdown", fuera);
  }, [estado]);
  // Al cambiar de pantalla, ninguna tarjeta se queda abierta.
  useEffect(() => {
    const cerrar = () => setEstado(null);
    window.addEventListener("hashchange", cerrar);
    return () => window.removeEventListener("hashchange", cerrar);
  }, []);
  return (
    <Contexto.Provider value={valor}>
      {children}
      <div id="en-tip" ref={tip} role="tooltip" className={estado ? `on${estado.tactil ? " tactil" : ""}` : undefined}
           style={estado ? posicion(estado.x, estado.y) : undefined}>
        {estado?.lineas.map((l, i) => (i === 0 ? <strong key={i}>{l}</strong> : <span key={i}>{l}</span>))}
        {estado?.destino && (estado.tactil
          ? <a className="en-tip-enlace" href={estado.destino}>{t.det_ver} →</a>
          : <span className="en-tip-pulsa">{t.det_pulsa}</span>)}
      </div>
    </Contexto.Provider>
  );
}

function posicion(x: number, y: number) {
  // A la derecha y por encima del puntero; si no cabe, al otro lado.
  const ancho = 300;
  const izquierda = x + 14 + ancho > window.innerWidth ? x - ancho - 14 : x + 14;
  return { left: Math.max(8, izquierda), top: Math.max(8, y - 12) };
}

const ir = (destino: string) => { window.location.hash = destino; };

/** Propiedades para un elemento con información emergente. La primera línea va en negrita. Con destino, el elemento
 *  lleva al detalle (clic, Intro o barra espaciadora; en pantalla táctil, primero la tarjeta con el enlace). */
export function useAyuda() {
  const { setEstado, actual } = useContext(Contexto);
  const ultimo = useRef<string[]>([]);
  const puntero = useRef("");
  const ocultar = useCallback(() => { if (!actual.current?.tactil) setEstado(null); }, [setEstado, actual]);
  return useCallback((lineas: string[], destino?: string) => ({
    tabIndex: 0,
    "aria-label": [...lineas, ...(destino ? [t.det_pulsa] : [])].join(". "),
    ...(destino ? { role: "link", "data-destino": destino } : {}),
    onMouseEnter: (e: MouseEvent) => {
      if (actual.current?.tactil) return;
      ultimo.current = lineas; setEstado({ lineas, x: e.clientX, y: e.clientY, destino });
    },
    onMouseMove: (e: MouseEvent) => { if (!actual.current?.tactil) setEstado({ lineas: ultimo.current, x: e.clientX, y: e.clientY, destino }); },
    onMouseLeave: ocultar,
    onFocus: (e: FocusEvent<HTMLElement>) => {
      if (actual.current?.tactil) return;
      const r = e.currentTarget.getBoundingClientRect();
      ultimo.current = lineas;
      setEstado({ lineas, x: r.left + r.width / 2, y: r.top, destino });
    },
    onBlur: ocultar,
    ...(destino ? {
      onPointerDown: (e: PointerEvent) => { puntero.current = e.pointerType; },
      onClick: (e: MouseEvent<HTMLElement>) => {
        const abierta = actual.current?.tactil && actual.current.origen === e.currentTarget;
        if (puntero.current === "touch" && !abierta) {
          const r = e.currentTarget.getBoundingClientRect();
          setEstado({ lineas, x: Math.min(r.left + 16, window.innerWidth - 316), y: r.bottom + 18, destino, tactil: true, origen: e.currentTarget });
          return;
        }
        setEstado(null);
        ir(destino);
      },
      onKeyDown: (e: KeyboardEvent) => {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); setEstado(null); ir(destino); }
      },
    } : {}),
  }), [setEstado, ocultar, actual]);
}
