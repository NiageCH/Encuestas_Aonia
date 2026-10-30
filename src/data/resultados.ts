// Acceso a los resultados. Todo pasa por las RPC agregadas: el cliente nunca ve respuestas
// individuales, y lo que llega ya trae aplicados permisos, mínimo de 5 y supresión
// complementaria.

import { CURSO, supabase } from "./cliente";
import { mayusculaInicial, textosConMayuscula } from "../formato";

export type Motivo = "menos_de_5" | "complementaria" | "sin_datos";

export interface Fila {
  clave: Record<string, string>;
  suprimido: boolean;
  motivo?: Motivo;
  n?: number;
  /** Visible con menos de 5 respuestas: solo para Dirección y administración (§5.0). */
  menos_de_5?: boolean;
  media?: number;
  n_personas?: number;
  n_valoraciones?: number;
  ns_nc?: number;
  distribucion?: Record<string, number>;
  promotores_pct?: number;
  neutros_pct?: number;
  detractores_pct?: number;
  nps?: number;
  opciones?: { codigo: string; n: number; pct: number }[];
}

export interface Resultado {
  total: Fila;
  partes: Fila[];
  dimensiones: string[];
}

export type Colectivo = "alumnos" | "familias" | "personal";

export interface Filtro {
  colectivo: Colectivo;
  cuestionario?: string;
  etapa?: string;
  etapas?: string[];
  grupo?: string;
  asignatura?: string;
  docente?: boolean;
  antiguedad?: "primer_ano" | "mas_de_un_ano";
  idioma?: "es" | "en";
  /** Coordinación en Familias: total del colegio como referencia (sin filtros ni repartos). */
  referencia?: true;
}

export type Metrica =
  | { tipo: "personas" }
  | { tipo: "satisfaccion" }
  | { tipo: "recomendacion" }
  | { tipo: "bloque"; codigo: string }
  | { tipo: "pregunta"; codigo: string }
  | { tipo: "seleccion"; codigo: string };

export async function resultados(filtro: Filtro, metrica: Metrica, dimensiones: string[] = []): Promise<Resultado> {
  const { data, error } = await supabase.rpc("resultados", {
    p_filtro: { curso: CURSO, ...filtro },
    p_metrica: metrica,
    p_dimensiones: dimensiones,
  });
  if (error) throw error;
  return data as Resultado;
}

export interface Cuestionario {
  codigo: string;
  titulo: string;
  etapa: string | null;
  respuestas_incompletas: number;
  idiomas_cargados: string[];
}

export async function cuestionarios(colectivo: Colectivo): Promise<Cuestionario[]> {
  const { data, error } = await supabase
    .from("cuestionario")
    .select("codigo, titulo, etapa, respuestas_incompletas, idiomas_cargados, curso!inner(nombre)")
    .eq("colectivo", colectivo)
    .eq("curso.nombre", CURSO)
    .order("id");
  if (error) throw error;
  return (data ?? []).map(({ codigo, titulo, etapa, respuestas_incompletas, idiomas_cargados }) => ({
    codigo, titulo, etapa, respuestas_incompletas, idiomas_cargados,
  }));
}

/** Colectivos con algún cuestionario cargado en el curso (para el estado vacío). Lo responde el servidor exigiendo un
 *  perfil activo y el doble factor del administrador: si no los hay, da error en lugar de una lista vacía. */
export async function colectivosCargados(): Promise<Colectivo[]> {
  const { data, error } = await supabase.rpc("colectivos_cargados", { p_curso: CURSO });
  if (error) throw error;
  return (data ?? []) as Colectivo[];
}

export interface Bloque {
  codigo: string;
  nombre: string;
  orden: number;
  entra_en_media: boolean;
}

export async function bloques(cuestionario: string): Promise<Bloque[]> {
  const { data, error } = await supabase
    .from("bloque")
    .select("codigo, nombre, orden, entra_en_media, cuestionario!inner(codigo, curso!inner(nombre))")
    .eq("cuestionario.codigo", cuestionario)
    .eq("cuestionario.curso.nombre", CURSO)
    .order("orden");
  if (error) throw error;
  return (data ?? []).map(({ codigo, nombre, orden, entra_en_media }) => ({ codigo, nombre, orden, entra_en_media }));
}

export interface DetallePregunta {
  codigo: string;
  texto: string;
  resultado: Resultado;
}

/** Cada pregunta de un bloque (por su código), en el orden del cuestionario. */
export async function detallePreguntas(filtro: Filtro, bloque: string, dimensiones: string[] = []): Promise<DetallePregunta[]> {
  const { data, error } = await supabase.rpc("detalle_preguntas", {
    p_filtro: { curso: CURSO, ...filtro },
    p_bloque: bloque,
    p_dimensiones: dimensiones,
  });
  if (error) throw error;
  return data as DetallePregunta[];   // enunciados tal como están guardados: la web y los PDF les ponen mayúscula inicial
}

export interface Ubicacion { cuestionario: string; etapa: string | null; bloque: string }

/** Dónde está cada pregunta de un colectivo (código del diccionario → cuestionarios y bloque, en el orden de los
 *  cuestionarios). Para llevar desde Inicio al detalle por pregunta de su pantalla. Solo estructura, ningún resultado. */
export async function ubicacionPreguntas(colectivo: Colectivo): Promise<Record<string, Ubicacion[]>> {
  const { data, error } = await supabase
    .from("pregunta_cuestionario")
    .select("pregunta!inner(codigo_diccionario), bloque!inner(codigo), cuestionario!inner(id, codigo, etapa, colectivo, curso!inner(nombre))")
    .eq("cuestionario.colectivo", colectivo)
    .eq("cuestionario.curso.nombre", CURSO);
  if (error) throw error;
  type Fila = { pregunta: { codigo_diccionario: string }; bloque: { codigo: string }; cuestionario: { id: number; codigo: string; etapa: string | null } };
  const r: Record<string, (Ubicacion & { id: number })[]> = {};
  for (const x of (data ?? []) as unknown as Fila[]) {
    (r[x.pregunta.codigo_diccionario] ??= []).push({ cuestionario: x.cuestionario.codigo, etapa: x.cuestionario.etapa, bloque: x.bloque.codigo, id: x.cuestionario.id });
  }
  return Object.fromEntries(Object.entries(r).map(([k, v]) => [k, v.sort((a, b) => a.id - b.id).map(({ id: _, ...u }) => u)]));
}

/** Texto de cada opción de una pregunta de selección múltiple (código -> texto). */
export async function opciones(pregunta: string): Promise<Record<string, string>> {
  const { data, error } = await supabase
    .from("opcion")
    .select("codigo, texto_es, pregunta!inner(codigo_diccionario)")
    .eq("pregunta.codigo_diccionario", pregunta);
  if (error) throw error;
  return Object.fromEntries((data ?? []).map((o) => [o.codigo, o.texto_es]));
}

/** Recuento informativo de personas por idioma en personal (cifras exactas, §5): no existe
 *  ningún resultado desagregado por idioma. */
export async function recuentoIdiomas(): Promise<Record<string, number>> {
  const { data, error } = await supabase.rpc("recuento_idiomas", { p_curso: CURSO });
  if (error) throw error;
  return (data ?? {}) as Record<string, number>;
}

export interface PreguntaComun {
  codigo: string;
  texto: string;
  /** colectivo -> código de la pregunta en el diccionario */
  preguntas: Partial<Record<Colectivo, string>>;
}

/** Preguntas comunes entre colectivos (§7.1), candidatas pendientes de confirmar con el colegio. */
export async function preguntasComunes(): Promise<PreguntaComun[]> {
  const { data, error } = await supabase
    .from("pregunta_comun")
    .select("codigo_comun, texto_es, colectivo, pregunta!inner(codigo_diccionario)");
  if (error) throw error;
  const porCodigo = new Map<string, PreguntaComun>();
  for (const fila of (data ?? []) as unknown as { codigo_comun: string; texto_es: string; colectivo: Colectivo; pregunta: { codigo_diccionario: string } }[]) {
    const c = porCodigo.get(fila.codigo_comun) ?? { codigo: fila.codigo_comun, texto: fila.texto_es, preguntas: {} };
    c.preguntas[fila.colectivo] = fila.pregunta.codigo_diccionario;
    porCodigo.set(fila.codigo_comun, c);
  }
  return [...porCodigo.values()];
}

export interface Profesor {
  id: number;
  nombre: string;
  apellidos: string;
  departamento: string | null;
  situacion?: "alta" | "baja";
}

/** Profesores con docencia en el curso (la coordinación solo recibe los de su etapa). */
export async function listarProfesores(): Promise<Profesor[]> {
  const { data, error } = await supabase.rpc("listar_profesores", { p_curso: CURSO });
  if (error) throw error;
  return (data ?? []) as Profesor[];
}

/** Docentes que dan una asignatura en un cuestionario (y en un grupo): solo identificadores, para limitar la lista del
 *  profesorado al pulsar una asignatura en Alumnado. La coordinación solo recibe los de su etapa. */
export async function profesoresDeClase(filtro: { cuestionario: string; asignatura: string; grupo?: string }): Promise<number[]> {
  const { data, error } = await supabase.rpc("profesores_de_clase", { p_curso: CURSO, p_filtro: filtro });
  if (error) throw error;
  return (data ?? []) as number[];
}

export interface CeldaProfesor extends Fila {
  etapa: string;
  /** propia: único docente · atribuida: alumnos que escribieron su nombre · compartida: varios docentes */
  tipo: "propia" | "atribuida" | "compartida";
  docentes_clase: number;
}

export interface GlobalProfesor {
  suprimido: boolean; motivo?: string; combinaciones?: number; n_personas_por_asignatura?: number; n_valoraciones?: number; media?: number;
  /** Clases con menos de 5 respuestas que entran en la media (solo en la versión completa). */
  menos_de_5?: number;
}

export interface ResultadoProfesor {
  docente: { id: number; nombre: string; apellidos: string };
  celdas: CeldaProfesor[];
  global: GlobalProfesor;
  /** Solo en la versión completa (Dirección y administración): la media global tal como sale en la versión docente. */
  global_docente?: GlobalProfesor;
  combinaciones_excluidas: number;
  compartidas: number;
  comparacion: Record<string, Fila>;
}

/** Resultados de un profesor en las encuestas de alumnos (§7.2 y §5.3). */
export async function resultadosProfesor(docente: number, metrica: Metrica = { tipo: "bloque", codigo: "profesorado" }): Promise<ResultadoProfesor> {
  const { data, error } = await supabase.rpc("resultados_profesor", { p_curso: CURSO, p_docente: docente, p_metrica: metrica });
  if (error) throw error;
  return data as ResultadoProfesor;
}

export interface PreguntaBloque { codigo: string; texto: string; orden: number }

/** Preguntas del bloque de profesorado de unos cuestionarios, sin repetir, en orden. */
export async function preguntasProfesorado(cuestionarios: string[]): Promise<PreguntaBloque[]> {
  const { data, error } = await supabase
    .from("pregunta_cuestionario")
    .select("orden, pregunta!inner(codigo_diccionario, texto_es), bloque!inner(codigo), cuestionario!inner(codigo, curso!inner(nombre))")
    .eq("bloque.codigo", "profesorado")
    .eq("cuestionario.curso.nombre", CURSO)
    .in("cuestionario.codigo", cuestionarios)
    .order("orden");
  if (error) throw error;
  const vistos = new Map<string, PreguntaBloque>();
  for (const f of (data ?? []) as unknown as { orden: number; pregunta: { codigo_diccionario: string; texto_es: string } }[]) {
    if (!vistos.has(f.pregunta.codigo_diccionario)) {
      vistos.set(f.pregunta.codigo_diccionario, { codigo: f.pregunta.codigo_diccionario, texto: mayusculaInicial(f.pregunta.texto_es), orden: f.orden });
    }
  }
  return [...vistos.values()];
}

/** completa: la de Dirección y administración, con todo y la marca «menos de 5». docente: la que recibe el docente, con el
 *  mínimo de 5 y la complementaria (§5.0). La coordinación siempre recibe la docente. */
export type VersionInforme = "completa" | "docente";

export type InformeProfesor = ResultadoProfesor & {
  preguntas: { codigo: string; texto: string; resultado: ResultadoProfesor }[];
  version: VersionInforme;
};

/** Informe de un profesor (bloque, cada pregunta y cada pregunta en cada clase) para el PDF. Queda en el registro de
 *  actividad, con la versión y si forma parte de un lote. */
export async function informeProfesor(docente: number, lote = false, version: VersionInforme = "completa"): Promise<InformeProfesor> {
  const { data, error } = await supabase.rpc("informe_profesor", { p_curso: CURSO, p_docente: docente, p_lote: lote, p_version: version });
  if (error) throw error;
  return textosConMayuscula(data as InformeProfesor);
}

export type TipoResponsable = "equipo_individualizacion" | "departamento" | "superiores" | "centro";

export interface InformeResponsable {
  tipo: TipoResponsable;
  ambito: string | null;
  bloque: string;
  total: Fila;
  preguntas: DetallePregunta[];
}

/** Informe de responsables por ámbito (§7.3). Solo administración y dirección. Con
 *  registrar = true (PDF), la generación queda en el registro de actividad. */
export async function informeResponsable(tipo: TipoResponsable, ambito: string | null = null, registrar = false): Promise<InformeResponsable> {
  const { data, error } = await supabase.rpc("informe_responsable", { p_curso: CURSO, p_tipo: tipo, p_ambito: ambito, p_registrar: registrar });
  if (error) throw error;
  return textosConMayuscula(data as InformeResponsable);
}

export interface MediaDepartamentoAlumnos {
  profesores: number;
  global: GlobalProfesor;
  combinaciones_excluidas: number;
}

/** Media de los profesores de un departamento según los alumnos (solo combinaciones visibles). */
export async function mediaDepartamentoAlumnos(departamento: string): Promise<MediaDepartamentoAlumnos> {
  const { data, error } = await supabase.rpc("media_departamento_alumnos", { p_curso: CURSO, p_departamento: departamento });
  if (error) throw error;
  return data as MediaDepartamentoAlumnos;
}

export interface Jefe { id: number; nombre: string; apellidos: string; departamentos: string[] }

/** Jefes de departamento con sus departamentos oficiales. */
export async function listarJefes(): Promise<Jefe[]> {
  const { data, error } = await supabase.rpc("listar_jefes", { p_curso: CURSO });
  if (error) throw error;
  return (data ?? []) as Jefe[];
}

/** Departamento tal como aparece en la encuesta de personal → la jefatura que lo tiene en su informe (equivalencias de
 *  §7.3; sin equivalencia, el departamento oficial del mismo nombre). Para llevar del departamento a su informe. */
export async function jefaturaPorDepartamento(): Promise<Record<string, Jefe>> {
  const [jefes, deps, eq] = await Promise.all([
    listarJefes(),
    supabase.from("departamento").select("id, nombre, curso!inner(nombre)").eq("curso.nombre", CURSO),
    supabase.from("departamento_equivalencia").select("departamento_encuesta_id, departamento_id"),
  ]);
  if (deps.error) throw deps.error;
  if (eq.error) throw eq.error;
  const nombre = new Map((deps.data ?? []).map((d) => [d.id as number, d.nombre as string]));
  const oficiales = new Map<string, string[]>();
  for (const e of eq.data ?? []) {
    const de = nombre.get(e.departamento_encuesta_id), o = nombre.get(e.departamento_id);
    if (de && o) oficiales.set(de, [...(oficiales.get(de) ?? []), o]);
  }
  const r: Record<string, Jefe> = {};
  for (const d of nombre.values()) {
    const j = jefes.find((x) => (oficiales.get(d) ?? [d]).some((o) => x.departamentos.includes(o)));
    if (j) r[d] = j;
  }
  return r;
}

export interface SeccionReuniones {
  /** Departamentos tal como aparecen en la encuesta de personal */
  unidades: string[];
  /** true: varios departamentos ocultos por separado que se muestran juntos */
  conjunto: boolean;
  total: Fila;
  preguntas: DetallePregunta[];
}

export interface InformeJefe {
  persona: { id: number; nombre: string; apellidos: string };
  departamentos: string[];
  reuniones: SeccionReuniones[];
  /** Una sola media por jefe, con las clases propias visibles de todos sus departamentos. */
  alumnos: { departamentos: string[]; media: MediaDepartamentoAlumnos };
  version: VersionJefatura;
}

/** Informe de un jefe de departamento con todos sus departamentos (§7.3). */
/** completa: Dirección y administración, con lo de menos de 5 («no entregar a la jefatura»). jefatura: con el mínimo de 5
 *  y la complementaria; es la que se envía siempre a la jefatura (28/10/2026). */
export type VersionJefatura = "completa" | "jefatura";

export async function informeJefe(persona: number, registrar = false, version: VersionJefatura = "completa"): Promise<InformeJefe> {
  const { data, error } = await supabase.rpc("informe_jefe_departamento", { p_curso: CURSO, p_persona: persona, p_registrar: registrar, p_version: version });
  if (error) throw error;
  return textosConMayuscula(data as InformeJefe);
}

export interface GrupoEquipo {
  tramos: string[];
  responsables: { nombre: string; apellidos: string; tramo: string }[];
}

/** Resultados del Equipo de Individuación por tramo: los visibles por separado y los ocultos juntos. */
export async function listarEquipo(version: VersionJefatura = "completa"): Promise<GrupoEquipo[]> {
  const { data, error } = await supabase.rpc("listar_equipo", { p_curso: CURSO, p_version: version });
  if (error) throw error;
  return (data ?? []) as GrupoEquipo[];
}

/** tramos: con los que ha salido el informe (en la versión para la jefatura, los de su grupo). */
export interface InformeEquipo { tramos: string[]; total: Fila; preguntas: DetallePregunta[]; version: VersionJefatura }

export async function informeEquipo(tramos: string[], registrar = false, version: VersionJefatura = "completa"): Promise<InformeEquipo> {
  const { data, error } = await supabase.rpc("informe_equipo", { p_curso: CURSO, p_tramos: tramos, p_registrar: registrar, p_version: version });
  if (error) throw error;
  return textosConMayuscula(data as InformeEquipo);
}

export interface Punto { codigo: string; texto: string; n: number; media: number; pct_bajo: number }

/** Aspectos con mayor y menor valoración de un colectivo: preguntas de 1 a 6 con 5 o más valoraciones. */
export async function puntosColectivo(colectivo: Colectivo): Promise<{ mejora: Punto[]; fuertes: Punto[] }> {
  const { data, error } = await supabase.rpc("puntos_colectivo", { p_filtro: { curso: CURSO, colectivo } });
  if (error) throw error;
  return data as { mejora: Punto[]; fuertes: Punto[] };
}

export interface BloqueComparado { bloque: string; nombre: string; no_recomienda: Fila; recomienda: Fila; diferencia: number | null }

/** Media de cada bloque entre quienes no recomendarían el Colegio (0 a 6) y quienes sí (9 y 10). */
export async function comparacionRecomendacion(colectivo: Colectivo): Promise<BloqueComparado[]> {
  const { data, error } = await supabase.rpc("comparacion_recomendacion", { p_curso: CURSO, p_colectivo: colectivo });
  if (error) throw error;
  return (data ?? []) as BloqueComparado[];
}
