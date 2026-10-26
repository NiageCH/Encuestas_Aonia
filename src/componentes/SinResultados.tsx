// Estado vacío de las pantallas de resultados: el curso todavía no tiene encuestas cargadas de
// ese colectivo. Es distinto de lo oculto por el anonimato («menos de 5» u «oculto»): aquí no hay
// nada que mostrar, y se dice con un mensaje propio en lugar de dejar secciones en blanco.

import { createContext, useContext, type ReactNode } from "react";
import { hayResultados, type EstadoCarga } from "../acceso";
import { CURSO } from "../data/cliente";
import { salir } from "../data/sesion";
import type { Colectivo } from "../data/resultados";
import { t } from "../i18n";

/** Qué hay cargado en el curso: cargando, la lista de colectivos, sin acceso o error. */
const Contexto = createContext<EstadoCarga>({ estado: "cargando" });

export function ProveedorCargados({ cargados, children }: { cargados: EstadoCarga; children: ReactNode }) {
  return <Contexto.Provider value={cargados}>{children}</Contexto.Provider>;
}

/** true si alguno de los colectivos tiene resultados cargados; true mientras no se sabe. */
export function useHayResultados(...colectivos: Colectivo[]): boolean {
  return hayResultados(useContext(Contexto), colectivos);
}

export function SinResultados({ colectivo }: { colectivo?: Colectivo }) {
  const carga = useContext(Contexto);
  // Si el servidor ha denegado o ha fallado, se dice eso: nunca «no hay resultados».
  if (carga.estado === "sin_acceso") {
    return (
      <div className="card en-vacio" role="alert">
        <span className="en-vacio-icono" aria-hidden="true">🔒</span>
        <div>
          <h2>{t.acceso_denegado}</h2>
          <p>{t.acceso_denegado_d}</p>
          <button type="button" className="btn primary" onClick={salir}>{t.acceso_volver}</button>
        </div>
      </div>
    );
  }
  if (carga.estado === "error") {
    return (
      <div className="card en-vacio" role="alert">
        <span className="en-vacio-icono" aria-hidden="true">⚠️</span>
        <div>
          <h2>{t.carga_fallida}</h2>
          <p>{t.carga_fallida_d}</p>
          <button type="button" className="btn primary" onClick={() => window.location.reload()}>{t.carga_reintentar}</button>
        </div>
      </div>
    );
  }
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
