// Criterio de anonimato según el rol (§5.0). Lo aplica el servidor; aquí solo se decide qué leyenda acompaña a los
// resultados: Dirección y administración ven también lo de menos de 5 (marcado); la coordinación, no.

import { t } from "./i18n";

export const veMenos5 = (rol: string | undefined) => rol === "direccion" || rol === "administrador";

/** Leyenda al pie de cada pantalla de resultados. */
export const leyendaAnonimato = (rol: string | undefined) =>
  veMenos5(rol) ? `${t.leyenda_direccion} ${t.aviso_cierre_direccion}` : `${t.leyenda_oculto} ${t.aviso_cierre}`;
