// Ajustes de la aplicación que dependen del entorno (variables de Vite del alojamiento).

/** Franja «Resultados en validación». Se quita con VITE_AVISO_VALIDACION=no en el alojamiento
 *  (y volviendo a desplegar) cuando el colegio dé los resultados por buenos. */
export const AVISO_VALIDACION = import.meta.env.VITE_AVISO_VALIDACION !== "no";
