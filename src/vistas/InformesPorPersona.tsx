// Informes por persona (§7.0 y §7.3), sección propia del menú, de arriba abajo en la jerarquía del colegio:
// Dirección, Equipos (Equipo de Individuación, todo o por tramo), Departamentos (por jefe, con
// sus departamentos) y Profesores. Cada nivel con su PDF. La coordinación solo llega a
// Profesores (los de su etapa); el servidor lo impone.

import { useEffect, useState } from "react";
import { CabeceraPreguntas, FilaPregunta, LeyendaAcuerdo, lineasOculto } from "../componentes/Graficos";
import { Migas } from "../componentes/Marco";
import { Oculto } from "../componentes/Oculto";
import { SinResultados, useHayResultados } from "../componentes/SinResultados";
import {
  informeEquipo, informeJefe, informeResponsable, listarEquipo, listarJefes,
  type DetallePregunta, type Fila, type GrupoEquipo, type InformeJefe, type InformeResponsable, type Jefe,
  type MediaDepartamentoAlumnos, type TipoResponsable,
} from "../data/resultados";
import { enumerar, notaReuniones, responsablesEquipo, textoAlumnos, tituloAlumnosJefe, tituloEquipo, tituloReuniones } from "../etiquetas";
import type { Perfil } from "../data/sesion";
import * as f from "../formato";
import { t } from "../i18n";
import { aHash, nivelesPermitidos, type Nivel } from "../navegacion";
import type { SeccionPedida } from "../pdf/generar";
import { InformesProfesor } from "./Profesores";

export function InformesPorPersona({ perfil, nivel }: { perfil: Perfil; nivel: Nivel }) {
  const niveles = nivelesPermitidos(perfil.rol);
  const hayPersonal = useHayResultados("personal");
  const hayAlumnos = useHayResultados("alumnos");
  return (
    <div className="page">
      <Migas actual={t.nav_informes} />
      <p className="eyebrow">{t.alu_eyebrow}</p>
      <h1>🗂️ {t.nav_informes}</h1>
      <p className="lead">{perfil.rol === "coordinacion" ? t.per_coord_lead : t.ipp_lead}</p>
      {niveles.length > 1 && (
        <nav className="chips en-noprint en-niveles" aria-label={t.ipp_niveles}>
          {niveles.map((n) => (
            <a key={n} className={`chip${n === nivel ? " on" : ""}`} aria-current={n === nivel ? "page" : undefined}
               href={aHash({ seccion: "/informes", nivel: n })}>
              {t.ipp_nivel[n]}
            </a>
          ))}
        </nav>
      )}
      {nivel !== "profesores" && !hayPersonal && <SinResultados colectivo="personal" />}
      {nivel === "direccion" && hayPersonal && <NivelDireccion />}
      {nivel === "equipos" && hayPersonal && <NivelEquipos />}
      {nivel === "departamentos" && hayPersonal && <NivelDepartamentos />}
      {nivel === "profesores" && (hayAlumnos ? <InformesProfesor perfil={perfil} /> : <SinResultados colectivo="alumnos" />)}
    </div>
  );
}

const SUPERIORES: SeccionPedida = {
  tipo: "superiores", ambito: null, titulo: t.resp_superiores, subtitulo: t.resp_superiores_sub,
  nota: t.per_superiores_nota, etiquetas: t.escala_acuerdo_per,
};
const CENTRO: SeccionPedida = {
  tipo: "centro", ambito: null, titulo: t.ipp_centro, subtitulo: t.ipp_centro_sub, etiquetas: t.escala_acuerdo_per,
};
const EQUIPO: SeccionPedida = {
  tipo: "equipo_individualizacion", ambito: null, titulo: t.resp_equipo, subtitulo: t.resp_equipo_sub, etiquetas: t.escala_acuerdo_per,
};

function NivelDireccion() {
  return (
    <>
      <h2 className="section-title">{t.ipp_nivel.direccion}</h2>
      <p className="sec-lead">{t.ipp_direccion_lead}</p>
      <BotonPdfNivel nombre="Direccion" titulo={t.ipp_nivel.direccion} subtitulo={t.ipp_direccion_lead} secciones={[SUPERIORES, CENTRO]} />
      <SeccionInforme seccion={SUPERIORES} />
      <SeccionInforme seccion={CENTRO} />
    </>
  );
}

function NivelEquipos() {
  const [grupos, setGrupos] = useState<GrupoEquipo[] | null>(null);
  const [elegido, setElegido] = useState<number>(-1);   // -1: todo el equipo
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { listarEquipo().then(setGrupos).catch(() => setError(t.error_datos)); }, []);
  const g = grupos && elegido >= 0 ? grupos[elegido] : null;

  return (
    <>
      <h2 className="section-title">{t.ipp_nivel.equipos}</h2>
      <p className="sec-lead">{t.ipp_equipos_lead}</p>
      {error && <p className="notice en-alerta en-alerta-neg" role="alert">{error}</p>}
      {grupos && (
        <div className="en-prof">
          <div className="card en-noprint">
            <ul className="en-prof-lista" aria-label={t.ipp_nivel.equipos}>
              <li>
                <button type="button" className={elegido === -1 ? "on" : undefined} aria-pressed={elegido === -1} onClick={() => setElegido(-1)}>
                  <strong>{t.eq_todo}</strong><small>{t.eq_todo_sub}</small>
                </button>
              </li>
              {grupos.map((x, i) => (
                <li key={x.tramos.join("-")}>
                  <button type="button" className={elegido === i ? "on" : undefined} aria-pressed={elegido === i} onClick={() => setElegido(i)}>
                    <strong>{tituloEquipo(x.tramos)}</strong>
                    {x.responsables.length > 0 && <small>{responsablesEquipo(x)}</small>}
                  </button>
                </li>
              ))}
            </ul>
            <p className="en-hint" style={{ marginTop: ".6rem" }}>{t.eq_sin_tramo}</p>
          </div>
          <div>
            {g ? (
              <>
                <div className="card">
                  <p className="eyebrow">{t.resp_informe}</p>
                  <h3 className="en-prof-nombre">{tituloEquipo(g.tramos)}</h3>
                  {g.responsables.length > 0 && <p className="en-hint">{t.eq_responsables}: {responsablesEquipo(g)}</p>}
                  <BotonPdf generar={async () => (await import("../pdf/generar")).descargarInformeEquipo(g)} />
                </div>
                <SeccionDatos key={g.tramos.join("-")} titulo={t.resp_equipo} subtitulo={t.eq_sub_tramo} etiquetas={t.escala_acuerdo_per}
                              nota={g.tramos.length > 1 ? t.eq_compartido_nota : undefined}
                              cargar={() => informeEquipo(g.tramos)} />
              </>
            ) : (
              <>
                <BotonPdfNivel nombre="Equipo_Individuacion" titulo={t.resp_equipo} subtitulo={t.resp_equipo_sub} secciones={[EQUIPO]} />
                <SeccionInforme seccion={EQUIPO} />
              </>
            )}
          </div>
        </div>
      )}
    </>
  );
}

function NivelDepartamentos() {
  const [jefes, setJefes] = useState<Jefe[] | null>(null);
  const [elegido, setElegido] = useState<Jefe | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    listarJefes().then((j) => { setJefes(j); setElegido(j[0] ?? null); }).catch(() => setError(t.error_datos));
  }, []);

  return (
    <>
      <h2 className="section-title">{t.ipp_nivel.departamentos}</h2>
      <p className="sec-lead">{t.ipp_departamentos_lead}</p>
      {error && <p className="notice en-alerta en-alerta-neg" role="alert">{error}</p>}
      {jefes && jefes.length === 0 && <p className="notice en-alerta">{t.jefe_sin_jefes}</p>}
      {jefes && jefes.length > 0 && (
        <div className="en-prof">
          <div className="card en-noprint">
            <ul className="en-prof-lista" aria-label={t.jefe_lista}>
              {jefes.map((j) => (
                <li key={j.id}>
                  <button type="button" className={elegido?.id === j.id ? "on" : undefined} aria-pressed={elegido?.id === j.id} onClick={() => setElegido(j)}>
                    <strong>{enumerar(j.departamentos)}</strong><small>{j.nombre} {j.apellidos}</small>
                  </button>
                </li>
              ))}
            </ul>
          </div>
          <div>{elegido && <InformeDeJefe key={elegido.id} jefe={elegido} />}</div>
        </div>
      )}
    </>
  );
}

function InformeDeJefe({ jefe }: { jefe: Jefe }) {
  const [inf, setInf] = useState<InformeJefe | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { informeJefe(jefe.id).then(setInf).catch(() => setError(t.error_datos)); }, [jefe.id]);
  if (error) return <p className="notice en-alerta en-alerta-neg" role="alert">{error}</p>;
  if (!inf) return <p className="en-cargando">{t.cargando}</p>;
  return (
    <>
      <div className="card">
        <p className="eyebrow">{t.resp_informe}</p>
        <h3 className="en-prof-nombre">{jefe.nombre} {jefe.apellidos}</h3>
        <p className="en-hint">{t.jefe_departamentos(inf.departamentos)}</p>
        <BotonPdf generar={async () => (await import("../pdf/generar")).descargarInformeJefe(jefe)} />
        <div className="en-kpis en-kpis3" style={{ marginTop: ".6rem" }}>
          <AlumnosDepartamento titulo={tituloAlumnosJefe(inf.alumnos.departamentos)} m={inf.alumnos.media} />
        </div>
      </div>
      {inf.reuniones.length === 0 && <p className="notice en-alerta" style={{ marginTop: ".9rem" }}>{t.jefe_sin_reuniones}</p>}
      {inf.reuniones.map((r) => (
        <DatosSeccion key={r.unidades.join("-")} titulo={tituloReuniones(r)} subtitulo={t.resp_departamento_sub} etiquetas={t.escala_acuerdo_dep}
                      nota={notaReuniones(r, inf.departamentos, inf.reuniones.length)} datos={r} />
      ))}
    </>
  );
}

function AlumnosDepartamento({ titulo, m }: { titulo: string; m: MediaDepartamentoAlumnos }) {
  const x = textoAlumnos(m);
  return (
    <div className="card en-kpi">
      <div className="l">{titulo}</div>
      <div className="v">{m.global.suprimido && m.global.motivo === "solo_compartidas" ? <span className="en-sin-media">{t.dep_solo_compartidas_corto}</span>
        : m.global.suprimido ? <span className="en-oculto">{m.global.motivo === "sin_asignacion" ? t.dep_alumnos_pendiente_corto : t.prof_sin_visibles}</span>
        : <>{f.media(m.global.media!)} <small>/ 6</small></>}</div>
      <div className="d">{m.global.suprimido ? "" : x.detalle}{x.nota && <><br />{x.nota}</>}</div>
    </div>
  );
}

/** Carga los datos de una sección y la pinta. */
function SeccionDatos(props: { titulo: string; subtitulo: string; etiquetas: string[]; nota?: string;
                               cargar: () => Promise<{ total: Fila; preguntas: DetallePregunta[] }> }) {
  const [datos, setDatos] = useState<{ total: Fila; preguntas: DetallePregunta[] } | null>(null);
  useEffect(() => {
    let vigente = true;
    props.cargar().then((d) => vigente && setDatos(d)).catch(() => {});
    return () => { vigente = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  if (!datos) return <p className="en-cargando">{t.cargando}</p>;
  return <DatosSeccion {...props} datos={datos} />;
}

function BotonPdf({ generar }: { generar: () => Promise<void> }) {
  const [estado, setEstado] = useState<"" | "generando" | "error">("");
  async function pulsar() {
    setEstado("generando");
    try { await generar(); setEstado(""); } catch { setEstado("error"); }
  }
  return (
    <p className="en-noprint">
      <button type="button" className="btn primary" onClick={pulsar} disabled={estado === "generando"}>
        📄 {estado === "generando" ? t.pdf_generando : t.pdf_descargar}
      </button>
      {estado === "error" && <span className="en-error" role="alert"> {t.pdf_error}</span>}
    </p>
  );
}

/** Media de un bloque y el detalle de cada pregunta (Dirección y todo el equipo). */
function SeccionInforme({ seccion }: { seccion: SeccionPedida }) {
  const [datos, setDatos] = useState<InformeResponsable | null>(null);
  useEffect(() => {
    let vigente = true;
    setDatos(null);
    informeResponsable(seccion.tipo as TipoResponsable, seccion.ambito).then((d) => vigente && setDatos(d)).catch(() => {});
    return () => { vigente = false; };
  }, [seccion.tipo, seccion.ambito]);
  if (!datos) return <p className="en-cargando">{t.cargando}</p>;
  return <DatosSeccion titulo={seccion.titulo} subtitulo={seccion.subtitulo} nota={seccion.nota} etiquetas={seccion.etiquetas} datos={datos} />;
}

function DatosSeccion({ titulo, subtitulo, nota, etiquetas, datos }: {
  titulo: string; subtitulo: string; nota?: string; etiquetas: string[]; datos: { total: Fila; preguntas: DetallePregunta[] };
}) {
  const tot = datos.total;
  return (
    <div className="card" style={{ marginTop: ".9rem" }}>
      <h3>{titulo}</h3>
      <p className="en-hint">{subtitulo}</p>
      <div className="en-kpis en-kpis3">
        <div className="card en-kpi hl">
          <div className="l">{t.resp_media_bloque}</div>
          <div className="v">{tot.suprimido ? <Oculto fila={tot} /> : <>{f.media(tot.media!)} <small>/ 6</small></>}</div>
          <div className="d">{tot.suprimido ? lineasOculto(tot) : t.tip_personas(f.recuento(tot.n!))}</div>
        </div>
      </div>
      {nota && <p className="notice en-alerta" style={{ marginTop: ".9rem" }}>{nota}</p>}
      {!tot.suprimido && (
        <div style={{ marginTop: ".9rem" }}>
          <LeyendaAcuerdo etiquetas={etiquetas} />
          <CabeceraPreguntas />
          {datos.preguntas.map((p) => <FilaPregunta key={p.codigo} texto={p.texto} fila={p.resultado.total} etiquetas={etiquetas} />)}
        </div>
      )}
    </div>
  );
}

function BotonPdfNivel(props: { nombre: string; titulo: string; subtitulo: string; secciones: SeccionPedida[] }) {
  const [estado, setEstado] = useState<"" | "generando" | "error">("");
  async function generar() {
    setEstado("generando");
    try {
      const { descargarInformeNivel } = await import("../pdf/generar");
      await descargarInformeNivel({ ...props, eyebrow: t.resp_informe });
      setEstado("");
    } catch {
      setEstado("error");
    }
  }
  return (
    <p className="en-noprint">
      <button type="button" className="btn primary" onClick={generar} disabled={estado === "generando"}>
        📄 {estado === "generando" ? t.pdf_generando : t.pdf_descargar}
      </button>
      {estado === "error" && <span className="en-error" role="alert"> {t.pdf_error}</span>}
    </p>
  );
}
