// Estado vacío de las pantallas de resultados: el curso todavía no tiene encuestas cargadas de
// ese colectivo. Es distinto de lo oculto por el anonimato («menos de 5» u «oculto»): aquí no hay
// nada que mostrar, y se dice con un mensaje propio en lugar de dejar secciones en blanco.

import { createContext, useContext, type ReactNode } from "react";
import { CURSO } from "../data/cliente";
import type { Colectivo } from "../data/resultados";
import { t } from "../i18n";

/** Colectivos con encuestas cargadas en el curso (undefined: todavía cargando). */
const Contexto = createContext<Colectivo[] | undefined>(undefined);

export function ProveedorCargados({ cargados, children }: { cargados: Colectivo[] | undefined; children: ReactNode }) {
  return <Contexto.Provider value={cargados}>{children}</Contexto.Provider>;
}

/** true si alguno de los colectivos tiene resultados cargados; true mientras no se sabe. */
export function useHayResultados(...colectivos: Colectivo[]): boolean {
  const cargados = useContext(Contexto);
  return cargados === undefined || colectivos.some((c) => cargados.includes(c));
}

export function SinResultados({ colectivo }: { colectivo?: Colectivo }) {
  return (
    <div className="card en-vacio" role="status">
      <span className="en-vacio-icono" aria-hidden="true">🗂️</span>
      <div>
        <h2>{t.vacio_titulo(CURSO)}</h2>
        <p>{colectivo ? t.vacio_colectivo[colectivo] : t.vacio_general}</p>
        <p className="en-hint">{t.vacio_no_es_oculto}</p>
      </div>
    </div>
  );
}
