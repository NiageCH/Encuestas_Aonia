"""Carga de las encuestas 2025/26 en la base de datos.

Uso (desde la raíz del repositorio, con el entorno de etl/requirements.txt):
    .venv/bin/python etl/cargar_2526.py            # base de datos local de Supabase
    .venv/bin/python etl/cargar_2526.py --ensayo   # convierte y muestra el resumen, sin cargar

Lee los ficheros de datos_locales/fuentes/, los convierte (cuestionarios_2526.py) y los carga
en una sola transacción. Se puede repetir: borra antes los cuestionarios y respuestas del
curso. Escribe un informe de la carga en datos_locales/informes/ (fuera de git).

Conexión: variable DATABASE_URL (en .env); por defecto, la base de datos local en el puerto
55422. Para cualquier otra dirección hay que pasar --remoto, para no cargar por error en la
nube.
"""

from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "etl"))

from cuestionarios_2526 import CURSO, Cuestionario, Diccionario, convertir_todo  # noqa: E402
from preguntas_comunes_2526 import cargar_comunes  # noqa: E402
from departamentos_2526 import EQUIVALENCIAS_ENCUESTA, OFICIALES  # noqa: E402

LOCAL = "postgresql://postgres:postgres@127.0.0.1:55422/postgres"


def leer_env() -> Dict[str, str]:
    env = {}
    f = RAIZ / ".env"
    if f.exists():
        for linea in f.read_text().splitlines():
            if "=" in linea and not linea.lstrip().startswith("#"):
                k, v = linea.split("=", 1)
                env[k.strip()] = v.strip().strip('"')
    return env


def url_bd(remoto: bool) -> str:
    url = os.environ.get("DATABASE_URL") or leer_env().get("DATABASE_URL") or LOCAL
    es_local = "127.0.0.1" in url or "localhost" in url
    if not es_local and not remoto:
        sys.exit("DATABASE_URL no es local. Usa --remoto si de verdad quieres cargar ahí.")
    return url


def cargar(conn, dic: Diccionario, cuestionarios: List[Cuestionario]) -> list:
    """Carga todo y devuelve el resumen de la atribución a docentes (solo cifras)."""
    from atribucion_2526 import ALEXIA, atribuir, leer_alexia, nombre_y_apellidos
    alexia = leer_alexia() if ALEXIA.exists() else None
    resumen_atrib = []
    with conn.cursor() as cur:
        cur.execute("insert into public.curso (nombre) values (%s) on conflict (nombre) do nothing", (CURSO,))
        cur.execute("select id from public.curso where nombre = %s", (CURSO,))
        curso = cur.fetchone()[0]

        # Carga repetible: fuera lo anterior del curso (las respuestas caen en cascada).
        cur.execute("delete from public.cuestionario where curso_id = %s", (curso,))

        # Diccionario
        for p in dic.preguntas.values():
            cur.execute(
                """insert into public.pregunta (codigo_diccionario, texto_es, tipo, escala_min, escala_max, escala_pendiente)
                   values (%s, %s, %s, %s, %s, %s)
                   on conflict (codigo_diccionario) do update set texto_es = excluded.texto_es,
                     escala_pendiente = excluded.escala_pendiente
                   returning tipo::text, escala_min, escala_max""",
                (p.codigo, p.texto, p.tipo, p.escala_min, p.escala_max, p.escala_pendiente))
            if cur.fetchone() != (p.tipo, p.escala_min, p.escala_max):
                raise ValueError(f"La pregunta {p.codigo} ya existe con otro tipo o escala")
        cur.execute("select codigo_diccionario, id from public.pregunta")
        id_pregunta = dict(cur.fetchall())
        for pregunta, opciones in dic.opciones.items():
            for codigo, texto in opciones.items():
                cur.execute(
                    """insert into public.opcion (pregunta_id, codigo, texto_es) values (%s, %s, %s)
                       on conflict (pregunta_id, codigo) do update set texto_es = excluded.texto_es""",
                    (id_pregunta[pregunta], codigo, texto))
        cur.execute("select p.codigo_diccionario, o.codigo, o.id from public.opcion o join public.pregunta p on p.id = o.pregunta_id")
        id_opcion = {(p, c): i for p, c, i in cur.fetchall()}

        # Grupos, asignaturas y departamentos del curso
        def asegurar(tabla: str, nombre: str, extra: Dict[str, str] = None) -> int:
            extra = extra or {}
            cols = ", ".join(["curso_id", "nombre", *extra])
            marcas = ", ".join(["%s"] * (2 + len(extra)))
            cur.execute(f"insert into public.{tabla} ({cols}) values ({marcas}) on conflict (curso_id, nombre) do nothing",
                        (curso, nombre, *extra.values()))
            cur.execute(f"select id from public.{tabla} where curso_id = %s and nombre = %s", (curso, nombre))
            return cur.fetchone()[0]

        cache: Dict[tuple, int] = {}

        # Departamentos oficiales y los de la matriz de reuniones de la encuesta, con su
        # equivalencia (un departamento de la encuesta puede cubrir varios oficiales).
        def departamento(nombre: str) -> int:
            cur.execute("""insert into public.departamento (curso_id, nombre, oficial) values (%s, %s, %s)
                           on conflict (curso_id, nombre) do update set oficial = excluded.oficial returning id""",
                        (curso, nombre, nombre in OFICIALES))
            return cur.fetchone()[0]

        for nombre in OFICIALES:
            cache[("departamento", nombre)] = departamento(nombre)
        for nombre, oficiales in EQUIVALENCIAS_ENCUESTA.items():
            cache[("departamento", nombre)] = enc = departamento(nombre)
            for o in oficiales:
                cur.execute("insert into public.departamento_equivalencia values (%s, %s) on conflict do nothing",
                            (enc, cache[("departamento", o)]))

        def id_de(tabla: str, nombre: str, **extra) -> int:
            clave = (tabla, nombre)
            if clave not in cache:
                cache[clave] = asegurar(tabla, nombre, extra)
            return cache[clave]

        for c in cuestionarios:
            cur.execute(
                """insert into public.cuestionario (curso_id, colectivo, etapa, codigo, titulo, respuestas_incompletas, idiomas_cargados)
                   values (%s, %s, %s, %s, %s, %s, array[%s])
                   on conflict (curso_id, codigo) do update set
                     respuestas_incompletas = public.cuestionario.respuestas_incompletas + excluded.respuestas_incompletas,
                     idiomas_cargados = (select array_agg(distinct x order by x)
                                         from unnest(public.cuestionario.idiomas_cargados || excluded.idiomas_cargados) x)
                   returning id""",
                (curso, c.colectivo, c.etapa, c.codigo, c.titulo, c.abandonadas, c.idioma))
            id_cuest = cur.fetchone()[0]

            id_bloque = {}
            for b in c.bloques.values():
                cur.execute(
                    """insert into public.bloque (cuestionario_id, codigo, nombre, orden, entra_en_media)
                       values (%s, %s, %s, %s, %s)
                       on conflict (cuestionario_id, codigo) do update set nombre = excluded.nombre
                       returning id""",
                    (id_cuest, b.codigo, b.nombre, b.orden, b.entra_en_media))
                id_bloque[b.codigo] = cur.fetchone()[0]
            for pc in c.preguntas_cuest.values():
                cur.execute(
                    """insert into public.pregunta_cuestionario
                         (cuestionario_id, pregunta_id, bloque_id, orden, por_asignatura, por_departamento)
                       values (%s, %s, %s, %s, %s, %s) on conflict do nothing""",
                    (id_cuest, id_pregunta[pc.pregunta], id_bloque[pc.bloque], pc.orden, pc.por_asignatura, pc.por_departamento))

            items, opciones, etapas, tramos, rids = [], [], [], [], []
            for r in c.respuestas:
                grupo = None
                if r.grupo:
                    nivel = r.grupo.split()[0]
                    grupo = id_de("grupo", r.grupo, etapa=c.etapa, nivel=nivel)
                cur.execute(
                    """insert into privado.respuesta (cuestionario_id, grupo_id, idioma_origen, docente, antiguedad)
                       values (%s, %s, %s, %s, %s) returning id""",
                    (id_cuest, grupo, c.idioma, r.docente, r.antiguedad))
                rid = cur.fetchone()[0]
                rids.append(rid)
                # Tramo de tutoría: solo de quien contestó el bloque del Equipo de Individuación.
                if r.tramo in ("infantil", "y1_y5", "y6_y9", "y10_y12") and any(
                        i.valor is not None and c.preguntas_cuest[(i.pregunta, None)].bloque == "equipo_individualizacion"
                        for i in r.items):
                    tramos.append((rid, r.tramo))
                for e in sorted(r.etapas):
                    etapas.append((rid, e))
                for i in r.items:
                    items.append((rid, id_pregunta[i.pregunta],
                                  id_de("asignatura", i.asignatura) if i.asignatura else None,
                                  cache[("departamento", i.departamento)] if i.departamento and ("departamento", i.departamento) in cache
                                  else (id_de("departamento", i.departamento, oficial=i.departamento in OFICIALES) if i.departamento else None),
                                  i.valor, i.ns_nc))
                for pregunta, op in r.opciones:
                    opciones.append((rid, id_pregunta[pregunta], id_opcion[(pregunta, op)]))

            cur.executemany("insert into privado.respuesta_etapa (respuesta_id, etapa) values (%s, %s)", etapas)
            cur.executemany("insert into privado.respuesta_tramo (respuesta_id, tramo) values (%s, %s)", tramos)
            with cur.copy("copy privado.respuesta_item (respuesta_id, pregunta_id, asignatura_id, departamento_id, valor, ns_nc) from stdin") as cp:
                for fila in items:
                    cp.write_row(fila)
            with cur.copy("copy privado.respuesta_opcion (respuesta_id, pregunta_id, opcion_id) from stdin") as cp:
                for fila in opciones:
                    cp.write_row(fila)
            print(f"  {c.codigo:10} {len(c.respuestas):4} respuestas · {len(items):6} valoraciones · {len(opciones):5} opciones")

            # Atribución a un docente por el nombre escrito (el texto no se carga).
            if alexia and c.colectivo == "alumnos":
                atribuciones, res = atribuir(alexia, c.codigo, c.respuestas)
                resumen_atrib += res
                for n, asignatura, correo in atribuciones:
                    nombre, apellidos = nombre_y_apellidos(alexia, correo)
                    cur.execute("""insert into public.persona_responsable (nombre, apellidos, correo) values (%s, %s, %s)
                                   on conflict (correo) do update set correo = excluded.correo returning id""",
                                (nombre, apellidos, correo))
                    docente = cur.fetchone()[0]
                    cur.execute("insert into privado.respuesta_docente (respuesta_id, asignatura_id, docente_id) values (%s, %s, %s)",
                                (rids[n], id_de("asignatura", asignatura), docente))
    return resumen_atrib


def informe(dic: Diccionario, cuestionarios: List[Cuestionario]) -> str:
    l = [f"# Informe de carga {CURSO}", "", f"Generado el {datetime.now():%d/%m/%Y %H:%M}. No subir a git.", "",
         "| Cuestionario | Filas | Abandonadas (incluidas) | Sin ninguna respuesta válida (no se cargan) | "
         "Excluidas por no indicar segmento | Cargadas | Bloques | Preguntas |",
         "|---|---|---|---|---|---|---|---|"]
    for c in cuestionarios:
        l.append(f"| {c.codigo} · {c.titulo} ({c.idioma}) | {c.filas} | {c.abandonadas} | {c.sin_datos} | "
                 f"{c.excluidas_sin_segmento} | {len(c.respuestas)} | "
                 f"{len(c.bloques)} | {len(c.preguntas_cuest)} |")
    l += ["", "## Exclusiones", "",
          "- Personal: se excluyen las respuestas que no indican si la persona es docente o su antigüedad. "
          "Formarían un segmento «sin dato» de una o dos personas, que se podría deducir restando los segmentos al total "
          "(decisión del 14/10/2026). No cuentan en ningún resultado de personal."]
    for c in cuestionarios:
        if c.excluidas_sin_segmento:
            l.append(f"- **{c.codigo}:** {c.excluidas_sin_segmento} respuesta(s) excluida(s) por no indicar segmento.")
    l += ["", "## Columnas descartadas", ""]
    for c in cuestionarios:
        l.append(f"- **{c.codigo}:** " + "; ".join(f"{k} ({v})" for k, v in sorted(c.descartes.items())))
    l += ["", "## Avisos", ""]
    for c in cuestionarios:
        for k, v in c.avisos.items():
            l.append(f"- **{c.codigo}:** {k}: {v}")
    l += ["", f"## Diccionario: {len(dic.preguntas)} preguntas", ""]
    for p in sorted(dic.preguntas.values(), key=lambda p: p.codigo):
        escala = f"{p.escala_min} a {p.escala_max}" if p.escala_min is not None else "selección múltiple"
        l.append(f"- `{p.codigo}` ({p.tipo}, {escala}){' · escala pendiente' if p.escala_pendiente else ''}: {p.texto}")
    return "\n".join(l) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ensayo", action="store_true", help="convierte y resume, sin tocar la base de datos")
    ap.add_argument("--remoto", action="store_true", help="permite una DATABASE_URL que no sea local")
    args = ap.parse_args()

    dic, cuestionarios = convertir_todo(RAIZ / "datos_locales" / "fuentes")
    carpeta = RAIZ / "datos_locales" / "informes"
    carpeta.mkdir(exist_ok=True)
    (carpeta / "carga_2526.md").write_text(informe(dic, cuestionarios))
    print(f"Convertidos {len(cuestionarios)} cuestionarios, {len(dic.preguntas)} preguntas en el diccionario.")
    print("Informe: datos_locales/informes/carga_2526.md")
    if args.ensayo:
        return

    import psycopg
    with psycopg.connect(url_bd(args.remoto)) as conn:
        resumen = cargar(conn, dic, cuestionarios)
        with (carpeta / "carga_2526.md").open("a") as f:
            f.write("\n## Atribución a un docente por el nombre escrito\n\n"
                    "Solo cifras: el texto no se carga. Se aplica en clases con más de un docente.\n\n"
                    "| Cuestionario | Columna | Alumnos | Rellenan | Casan con un docente | Atribuidas | Aplicada |\n|---|---|---|---|---|---|---|\n")
            for r in resumen:
                pct = f"{100 * r.casan / r.rellenan:.0f} %" if r.rellenan else "-"
                f.write(f"| {r.cuestionario} | {r.columna} | {r.alumnos} | {r.rellenan} | {pct} | {r.atribuidas} | "
                        f"{'sí' if r.aplicada else 'no: ' + r.motivo} |\n")
        for r in resumen:
            print(f"  Atribución {r.cuestionario} {r.columna}: {'sí' if r.aplicada else 'no (' + r.motivo + ')'}, {r.atribuidas} respuestas")
        with conn.cursor() as cur:
            print(f"  Preguntas comunes (candidatas): {cargar_comunes(cur)} filas")
        conn.commit()
    print("Carga terminada.")


if __name__ == "__main__":
    main()
