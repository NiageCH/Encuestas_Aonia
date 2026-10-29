// Registro de descargas: antes de crear cada PDF, CSV o ZIP, el servidor lo anota y devuelve el código, el nombre de quien
// descarga y la hora, que se imprimen en el archivo. La pestaña «Descargas» de Accesos lo consulta (solo administración).

import { CURSO, supabase } from "./cliente";
import type { SelloDescarga } from "../exportacion/modelo";

export type TipoDescarga = "informe_profesor" | "informe_jefatura" | "informe_equipo" | "informe_direccion" | "vista_pdf" | "csv" | "zip";
export const TIPOS_DESCARGA: TipoDescarga[] = ["informe_profesor", "informe_jefatura", "informe_equipo", "informe_direccion", "vista_pdf", "csv", "zip"];

export interface DatosDescarga {
  /** De quién es el informe o de qué vista: «García Pérez, Ana», «Alumnado». */
  objeto: string;
  docente?: number;
  persona?: number;
  tramos?: string[];
  vista?: string;
  filtros?: Record<string, string>;
  archivo: string;
  /** Informe del profesor/a: versión completa o docente. */
  version?: "completa" | "docente" | "jefatura";
  /** Solo en un ZIP: sus informes, cada uno con su código. */
  informes?: { objeto: string; docente?: number }[];
}

interface Respuesta { codigo: string; nombre: string; fecha: string; informes: { objeto: string; docente?: number; codigo: string }[] }

export interface Descarga extends SelloDescarga {
  /** En un ZIP, el sello de cada informe, en el mismo orden. */
  informes: SelloDescarga[];
}

/** Anota la descarga en el servidor y devuelve su sello (y el de cada informe de un ZIP). Si falla, no se descarga. */
export async function registrarDescarga(tipo: TipoDescarga, datos: DatosDescarga): Promise<Descarga> {
  const { data, error } = await supabase.rpc("registrar_descarga", { p_tipo: tipo, p_datos: { curso: CURSO, ...datos } });
  if (error) throw error;
  const r = data as Respuesta;
  const fecha = new Date(r.fecha);
  return { codigo: r.codigo, nombre: r.nombre, fecha, informes: r.informes.map((i) => ({ codigo: i.codigo, nombre: r.nombre, fecha })) };
}

export interface FilaDescarga {
  fecha: string;
  usuario_id: string | null;
  persona: string;
  correo: string | null;
  codigo: string;
  tipo: TipoDescarga;
  curso?: string;
  objeto: string;
  vista?: string;
  filtros?: Record<string, string>;
  archivo?: string;
  informes?: { objeto: string; codigo: string }[];
}

export interface FiltrosDescargas { persona?: string; tipo?: TipoDescarga; desde?: string; hasta?: string; objeto?: string; codigo?: string }

export async function descargas(filtros: FiltrosDescargas): Promise<{ total: number; filas: FilaDescarga[]; personas: { id: string; nombre: string }[] }> {
  const limpio = Object.fromEntries(Object.entries(filtros).filter(([, v]) => v));
  const { data, error } = await supabase.rpc("admin_descargas", { p_filtros: limpio });
  if (error) throw error;
  return data;
}
