// Personal → Informes por persona (§7.0 y §7.3), de arriba abajo en la jerarquía del colegio:
// Dirección, Equipos, Departamentos y Profesores. Cada nivel con su PDF. La coordinación solo
// llega a Profesores (los de su etapa); el servidor lo impone.

import { useEffect, useState } from "react";
import { CabeceraPreguntas, FilaPregunta, LeyendaAcuerdo, lineasOculto } from "../componentes/Graficos";
import { Oculto } from "../componentes/Oculto";
import {
  informeResponsable, mediaDepartamentoAlumnos, resultados,
  type InformeResponsable, type MediaDepartamentoAlumnos, type TipoResponsable,
} from "../data/resultados";
import type { Perfil } from "../data/sesion";
import * as f from "../formato";
import { t } from "../i18n";
import { aHash, nivelesPermitidos, type Nivel } from "../navegacion";
import type { SeccionPedida } from "../pdf/generar";
import { InformesProfesor } from "./Profesores";

export function InformesPorPersona({ perfil, nivel }: { perfil: Perfil; nivel: Nivel }) {
  const niveles = nivelesPermitidos(perfil.rol);
  return (
    <section>
      {niveles.length > 1 && (
        <nav className="chips en-noprint en-niveles" aria-label={t.ipp_niveles}>
          {niveles.map((n) => (
            <a key={n} className={`chip${n === nivel ? " on" : ""}`} aria-current={n === nivel ? "page" : undefined}
               href={aHash({ seccion: "/personal", apartado: "informes", nivel: n })}>
              {t.ipp_nivel[n]}
            </a>
          ))}
        </nav>
      )}
      {nivel === "direccion" && <NivelDireccion />}
      {nivel === "equipos" && <NivelEquipos />}
      {nivel === "departamentos" && <NivelDepartamentos />}
      {nivel === "profesores" && <InformesProfesor perfil={perfil} />}
    </section>
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
  return (
    <>
      <h2 className="section-title">{t.ipp_nivel.equipos}</h2>
      <p className="sec-lead">{t.ipp_equipos_lead}</p>
      <BotonPdfNivel nombre="Equipo_Individualizacion" titulo={t.resp_equipo} subtitulo={t.resp_equipo_sub} secciones={[EQUIPO]} />
      <SeccionInforme seccion={EQUIPO} />
    </>
  );
}

function NivelDepartamentos() {
  const [deps, setDeps] = useState<string[] | null>(null);
  const [ocultos, setOcultos] = useState(0);
  const [elegido, setElegido] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    resultados({ colectivo: "personal" }, { tipo: "bloque", codigo: "reuniones_departamento" }, ["departamento"])
      .then((r) => {
        // Solo los departamentos con su resultado visible (5 o más personas).
        const visibles = r.partes.filter((p) => !p.suprimido).map((p) => p.clave.departamento).sort((a, b) => a.localeCompare(b, "es"));
        setDeps(visibles);
        setOcultos(r.partes.filter((p) => p.suprimido).length);
        setElegido(visibles[0] ?? null);
      })
      .catch(() => setError(t.error_datos));
  }, []);

  const seccion = (d: string): SeccionPedida => ({
    tipo: "departamento", ambito: d, titulo: t.ipp_reuniones, subtitulo: t.resp_departamento_sub, etiquetas: t.escala_acuerdo_dep,
  });

  return (
    <>
      <h2 className="section-title">{t.ipp_nivel.departamentos}</h2>
      <p className="sec-lead">{t.ipp_departamentos_lead}</p>
      {error && <p className="notice">{error}</p>}
      {deps && (
        <div className="en-prof">
          <div className="card en-noprint">
            <ul className="en-prof-lista" aria-label={t.ipp_nivel.departamentos}>
              {deps.map((d) => (
                <li key={d}>
                  <button type="button" className={elegido === d ? "on" : undefined} aria-pressed={elegido === d} onClick={() => setElegido(d)}>
                    <strong>{d}</strong>
                  </button>
                </li>
              ))}
            </ul>
            {ocultos > 0 && <p className="en-hint" style={{ marginTop: ".6rem" }}>{t.resp_ocultos(ocultos)}</p>}
          </div>
          <div>
            {elegido && (
              <>
                <div className="card">
                  <p className="eyebrow">{t.resp_informe}</p>
                  <h3 className="en-prof-nombre">{t.resp_departamento(elegido)}</h3>
                  <BotonPdfNivel nombre={`Departamento_${elegido}`} titulo={t.resp_departamento(elegido)} subtitulo={t.resp_departamento_sub}
                                 secciones={[seccion(elegido)]} departamento={elegido} />
                  <AlumnosDepartamento departamento={elegido} />
                </div>
                <SeccionInforme key={elegido} seccion={seccion(elegido)} />
              </>
            )}
          </div>
        </div>
      )}
    </>
  );
}

function AlumnosDepartamento({ departamento }: { departamento: string }) {
  const [m, setM] = useState<MediaDepartamentoAlumnos | null>(null);
  useEffect(() => {
    setM(null);
    mediaDepartamentoAlumnos(departamento).then(setM).catch(() => {});
  }, [departamento]);
  if (!m) return <p className="en-cargando">{t.cargando}</p>;
  return (
    <div className="en-kpis en-kpis3" style={{ marginTop: ".6rem" }}>
      <div className="card en-kpi">
        <div className="l">{t.dep_alumnos_media}</div>
        <div className="v">{m.global.suprimido
          ? <span className="en-oculto">{m.global.motivo === "sin_asignacion" ? t.dep_alumnos_pendiente_corto : t.prof_sin_visibles}</span>
          : <>{f.media(m.global.media!)} <small>/ 6</small></>}</div>
        <div className="d">{m.global.suprimido ? (m.global.motivo === "sin_asignacion" ? t.dep_alumnos_pendiente : "")
          : t.dep_alumnos_detalle(m.profesores, m.global.combinaciones!, f.recuento(m.global.n_valoraciones!))}</div>
      </div>
      {m.combinaciones_excluidas > 0 && <p className="en-hint" style={{ gridColumn: "span 2", alignSelf: "center" }}>{t.prof_excluidas(m.combinaciones_excluidas)}</p>}
    </div>
  );
}

/** Media de un bloque y el detalle de cada pregunta. */
function SeccionInforme({ seccion }: { seccion: SeccionPedida }) {
  const [datos, setDatos] = useState<InformeResponsable | null>(null);
  useEffect(() => {
    let vigente = true;
    setDatos(null);
    informeResponsable(seccion.tipo as TipoResponsable, seccion.ambito).then((d) => vigente && setDatos(d)).catch(() => {});
    return () => { vigente = false; };
  }, [seccion.tipo, seccion.ambito]);

  if (!datos) return <p className="en-cargando">{t.cargando}</p>;
  const tot = datos.total;
  return (
    <div className="card" style={{ marginTop: ".9rem" }}>
      <h3>{seccion.titulo}</h3>
      <p className="en-hint">{seccion.subtitulo}</p>
      <div className="en-kpis en-kpis3">
        <div className="card en-kpi hl">
          <div className="l">{t.resp_media_bloque}</div>
          <div className="v">{tot.suprimido ? <Oculto fila={tot} /> : <>{f.media(tot.media!)} <small>/ 6</small></>}</div>
          <div className="d">{tot.suprimido ? lineasOculto(tot) : t.tip_personas(f.recuento(tot.n!))}</div>
        </div>
      </div>
      {seccion.nota && <p className="notice" style={{ marginTop: ".9rem" }}>{seccion.nota}</p>}
      {!tot.suprimido && (
        <div style={{ marginTop: ".9rem" }}>
          <LeyendaAcuerdo etiquetas={seccion.etiquetas} />
          <CabeceraPreguntas />
          {datos.preguntas.map((p) => <FilaPregunta key={p.codigo} texto={p.texto} fila={p.resultado.total} etiquetas={seccion.etiquetas} />)}
        </div>
      )}
    </div>
  );
}

function BotonPdfNivel(props: { nombre: string; titulo: string; subtitulo: string; secciones: SeccionPedida[]; departamento?: string }) {
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
