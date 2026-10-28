// Respuestas abiertas (§7.9): solo Dirección y administración. Por colectivo y pregunta, con los filtros del colectivo
// (alumnado: etapa, cuestionario y grupo; familias: etapa; personal: docente o no docente, o antigüedad, de uno en uno).
// Los textos van tal cual y sueltos: nada los enlaza con las respuestas cerradas de la misma persona. Cada consulta y
// cada exportación quedan en el registro (la exportación, con su código y la marca de confidencialidad).

import { useEffect, useMemo, useState } from "react";
import { Exportar } from "../componentes/Exportar";
import { Migas } from "../componentes/Marco";
import {
  gruposAbiertas, preguntasAbiertas, respuestasAbiertas,
  type FiltroAbiertas, type PreguntaAbierta, type ResultadoAbiertas,
} from "../data/abiertas";
import type { Colectivo } from "../data/resultados";
import { txt, type Exportacion } from "../exportacion/modelo";
import { t } from "../i18n";

const COLECTIVOS: Colectivo[] = ["alumnos", "familias", "personal"];
const SEGMENTOS = [
  { clave: "todos", seg: {}, texto: t.per_todos },
  { clave: "docentes", seg: { docente: true }, texto: t.per_docentes },
  { clave: "no_docentes", seg: { docente: false }, texto: t.per_no_docentes },
  { clave: "primer_ano", seg: { antiguedad: "primer_ano" as const }, texto: t.per_primer_ano },
  { clave: "mas_de_un_ano", seg: { antiguedad: "mas_de_un_ano" as const }, texto: t.per_mas_de_un_ano },
];

export function Abiertas() {
  const [preguntas, setPreguntas] = useState<PreguntaAbierta[] | null>(null);
  const [colectivo, setColectivo] = useState<Colectivo>("alumnos");
  const [pregunta, setPregunta] = useState("");
  const [etapa, setEtapa] = useState("");
  const [cuestionario, setCuestionario] = useState("");
  const [grupo, setGrupo] = useState("");
  const [grupos, setGrupos] = useState<string[]>([]);
  const [segmento, setSegmento] = useState("todos");
  const [datos, setDatos] = useState<ResultadoAbiertas | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => { preguntasAbiertas().then(setPreguntas).catch(() => setError(t.error_datos)); }, []);

  const delColectivo = useMemo(() => (preguntas ?? []).filter((p) => p.colectivo === colectivo), [preguntas, colectivo]);
  // Preguntas por su código (la misma en varios cuestionarios), en el orden en que aparecen.
  const ORDEN = Object.keys(t.abi_preguntas);
  const codigos = useMemo(() => [...new Set(delColectivo.map((p) => p.codigo))]
    .sort((a, b) => (ORDEN.indexOf(a) + 1 || 99) - (ORDEN.indexOf(b) + 1 || 99)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [delColectivo]);
  const conPregunta = delColectivo.filter((p) => p.codigo === pregunta);
  const etapas = [...new Set(conPregunta.map((p) => p.etapa).filter(Boolean))] as string[];
  const cuestionarios = conPregunta.filter((p) => !etapa || p.etapa === etapa);

  useEffect(() => { setPregunta(codigos[0] ?? ""); }, [codigos]);
  useEffect(() => { setEtapa(""); setCuestionario(""); setGrupo(""); setSegmento("todos"); }, [colectivo, pregunta]);
  useEffect(() => {
    setGrupo(""); setGrupos([]);
    if (cuestionario) gruposAbiertas(cuestionario).then(setGrupos).catch(() => {});
  }, [cuestionario]);

  const filtro: FiltroAbiertas | null = pregunta ? {
    colectivo, pregunta,
    ...(etapa ? { etapa } : {}),
    ...(colectivo === "alumnos" && cuestionario ? { cuestionario } : {}),
    ...(colectivo === "alumnos" && grupo ? { grupo } : {}),
    ...(colectivo === "personal" ? SEGMENTOS.find((s) => s.clave === segmento)!.seg : {}),
  } : null;
  const clave = JSON.stringify(filtro);

  useEffect(() => {
    if (!filtro) return;
    let vigente = true;
    setDatos(null); setError(null);
    respuestasAbiertas(filtro).then((d) => vigente && setDatos(d)).catch(() => vigente && setError(t.error_datos));
    return () => { vigente = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clave]);

  const nombreEtapa = (e: string) => t.etapas[e as keyof typeof t.etapas] ?? e;
  const tituloPregunta = (c: string) => t.abi_preguntas[c as keyof typeof t.abi_preguntas] ?? delColectivo.find((p) => p.codigo === c)?.texto ?? c;
  const titulos = Object.fromEntries((preguntas ?? []).map((p) => [p.cuestionario, p.cuestionario_titulo]));
  const varios = new Set(datos?.respuestas.map((r) => r.cuestionario)).size > 1;

  async function preparar(): Promise<Exportacion> {
    const d = datos!;
    const filtros: [string, string][] = [
      [t.abi_colectivo, t.panel_colectivo[colectivo]], [t.abi_pregunta, tituloPregunta(pregunta)],
      ...(etapa ? [[t.abi_etapa, nombreEtapa(etapa)] as [string, string]] : []),
      ...(cuestionario ? [[t.cuestionario, titulos[cuestionario]] as [string, string]] : []),
      ...(grupo ? [[t.grupo, grupo] as [string, string]] : []),
      ...(colectivo === "personal" && segmento !== "todos" ? [[t.per_filtro, SEGMENTOS.find((s) => s.clave === segmento)!.texto] as [string, string]] : []),
    ];
    return {
      vista: "abiertas", titulo: t.abi_titulo, filtros,
      archivo: [t.abi_archivo, t.panel_colectivo[colectivo], pregunta],
      tablas: [{
        titulo: tituloPregunta(pregunta),
        columnas: varios ? [t.abi_col_respuesta, t.cuestionario] : [t.abi_col_respuesta],
        filas: d.respuestas.map((r) => varios ? [txt(r.texto), txt(titulos[r.cuestionario] ?? r.cuestionario)] : [txt(r.texto)]),
        notas: d.preguntas.map((p) => `${p.cuestionario_titulo}: «${p.texto}»${p.nota ? ` (${p.nota})` : ""}`),
      }],
      notas: [t.abi_nota_export],
    };
  }

  return (
    <div className="page">
      <Migas actual={t.abi_titulo} />
      <p className="eyebrow">{t.abi_eyebrow}</p>
      <h1>💬 {t.abi_titulo}</h1>
      <p className="lead">{t.abi_lead}</p>
      <p className="notice en-alerta">{t.abi_aviso}</p>

      {error && <p className="notice en-alerta en-alerta-neg" role="alert">{error}</p>}
      {preguntas && preguntas.length === 0 && <p className="notice en-alerta">{t.abi_sin_cargar}</p>}
      {preguntas && preguntas.length > 0 && (
        <>
          <div className="chips en-noprint" role="group" aria-label={t.abi_colectivo}>
            {COLECTIVOS.filter((c) => (preguntas ?? []).some((p) => p.colectivo === c)).map((c) => (
              <button key={c} className={`chip${colectivo === c ? " on" : ""}`} aria-pressed={colectivo === c} onClick={() => setColectivo(c)}>
                {t.panel_colectivo[c]}
              </button>
            ))}
          </div>

          <div className="card en-filters en-noprint">
            <label><span>{t.abi_pregunta}</span>
              <span className="en-select">
                <select value={pregunta} onChange={(e) => setPregunta(e.target.value)}>
                  {codigos.map((c) => (
                    <option key={c} value={c}>
                      {tituloPregunta(c)} ({delColectivo.filter((p) => p.codigo === c).reduce((a, p) => a + p.n, 0)})
                    </option>
                  ))}
                </select>
              </span>
            </label>
            {colectivo !== "personal" && etapas.length > 0 && (
              <label><span>{t.abi_etapa}</span>
                <span className="en-select">
                  <select value={etapa} onChange={(e) => { setEtapa(e.target.value); setCuestionario(""); }}>
                    <option value="">{t.abi_todas}</option>
                    {(colectivo === "familias" ? ["infantil", "primaria", "pai", "bachillerato"] : etapas).map((e) => (
                      <option key={e} value={e}>{nombreEtapa(e)}</option>
                    ))}
                  </select>
                </span>
              </label>
            )}
            {colectivo === "alumnos" && (
              <label><span>{t.cuestionario}</span>
                <span className="en-select">
                  <select value={cuestionario} onChange={(e) => setCuestionario(e.target.value)}>
                    <option value="">{t.abi_todos}</option>
                    {cuestionarios.map((p) => <option key={p.cuestionario} value={p.cuestionario}>{p.cuestionario_titulo} ({p.n})</option>)}
                  </select>
                </span>
              </label>
            )}
            {colectivo === "alumnos" && (
              <label><span>{t.grupo}</span>
                <span className="en-select">
                  <select value={grupo} onChange={(e) => setGrupo(e.target.value)} disabled={!cuestionario}>
                    <option value="">{cuestionario ? t.todos_grupos : t.abi_grupo_antes}</option>
                    {grupos.map((g) => <option key={g} value={g}>{g}</option>)}
                  </select>
                </span>
              </label>
            )}
          </div>
          {colectivo === "personal" && (
            <>
              <div className="chips en-noprint" role="group" aria-label={t.per_filtro}>
                {SEGMENTOS.map((s) => (
                  <button key={s.clave} className={`chip${segmento === s.clave ? " on" : ""}`} aria-pressed={segmento === s.clave}
                          onClick={() => setSegmento(s.clave)}>{s.texto}</button>
                ))}
              </div>
              <p className="en-hint">{t.per_filtro_nota}</p>
            </>
          )}

          <Exportar preparar={preparar} disabled={!datos || datos.n === 0} />

          {!datos && !error && <p className="en-cargando">{t.cargando}</p>}
          {datos && (
            <section className="card">
              <h3>{tituloPregunta(pregunta)}</h3>
              <p className="en-hint" role="status">{t.abi_n(datos.n)}</p>
              {datos.preguntas.some((p) => p.nota) && <p className="en-hint">{datos.preguntas.find((p) => p.nota)!.nota}</p>}
              {datos.n === 0 ? <p className="en-hint">{t.abi_vacio}</p> : (
                <ul className="en-abiertas">
                  {datos.respuestas.map((r, i) => (
                    <li key={i}>
                      <p>{r.texto}</p>
                      {varios && <small className="en-hint">{titulos[r.cuestionario] ?? r.cuestionario}</small>}
                    </li>
                  ))}
                </ul>
              )}
            </section>
          )}
        </>
      )}
    </div>
  );
}
