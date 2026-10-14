// Información emergente de los gráficos: aparece al pasar el ratón y también al llegar con
// el teclado (el elemento recibe el foco y lleva el mismo texto en aria-label).

import { createContext, useCallback, useContext, useRef, useState, type FocusEvent, type MouseEvent, type ReactNode } from "react";

interface Estado { lineas: string[]; x: number; y: number }

const Contexto = createContext<(e: Estado | null) => void>(() => {});

export function ProveedorAyuda({ children }: { children: ReactNode }) {
  const [estado, setEstado] = useState<Estado | null>(null);
  return (
    <Contexto.Provider value={setEstado}>
      {children}
      <div id="en-tip" role="tooltip" className={estado ? "on" : undefined}
           style={estado ? posicion(estado.x, estado.y) : undefined}>
        {estado?.lineas.map((l, i) => (i === 0 ? <strong key={i}>{l}</strong> : <span key={i}>{l}</span>))}
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

/** Propiedades para un elemento con información emergente. La primera línea va en negrita. */
export function useAyuda() {
  const setEstado = useContext(Contexto);
  const ultimo = useRef<string[]>([]);
  const ocultar = useCallback(() => setEstado(null), [setEstado]);
  return useCallback((lineas: string[]) => ({
    tabIndex: 0,
    "aria-label": lineas.join(". "),
    onMouseEnter: (e: MouseEvent) => { ultimo.current = lineas; setEstado({ lineas, x: e.clientX, y: e.clientY }); },
    onMouseMove: (e: MouseEvent) => setEstado({ lineas: ultimo.current, x: e.clientX, y: e.clientY }),
    onMouseLeave: ocultar,
    onFocus: (e: FocusEvent<HTMLElement>) => {
      const r = e.currentTarget.getBoundingClientRect();
      ultimo.current = lineas;
      setEstado({ lineas, x: r.left + r.width / 2, y: r.top });
    },
    onBlur: ocultar,
  }), [setEstado, ocultar]);
}
