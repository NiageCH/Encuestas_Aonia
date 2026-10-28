"""Carga de las respuestas abiertas de 2025/26 (especificación §7.9). Después de cargar_2526.py.

Uso (desde la raíz del repositorio):
    .venv/bin/python etl/cargar_abiertas_2526.py            # base de datos local de Supabase
    .venv/bin/python etl/cargar_abiertas_2526.py --ensayo   # solo el recuento de preguntas y respuestas, sin cargar

Se puede repetir: borra antes las preguntas abiertas de 2025/26 (y sus respuestas). Las respuestas se insertan en orden
aleatorio y con identificador aleatorio, para que ni el orden ni el número digan nada de quién respondió. En pantalla y en
el informe (datos_locales/informes/) solo salen cifras: ningún texto de respuesta.

Conexión: igual que cargar_2526.py (DATABASE_URL; para una base que no sea local hay que pasar --remoto).
"""

from __future__ import annotations

import argparse
import random
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "etl"))

from abiertas_2526 import extraer  # noqa: E402
from cargar_2526 import url_bd  # noqa: E402
from cuestionarios_2526 import CURSO  # noqa: E402


def resumen(preguntas, descartadas) -> list:
    lineas = ["| Cuestionario | Pregunta | Respuestas |", "|---|---|---:|"]
    for p in preguntas:
        nota = " (texto deducido: no viene en la exportación)" if p.nota else ""
        lineas.append(f"| {p.cuestionario} | {p.texto}{nota} | {len(p.respuestas)} |")
    total = sum(len(p.respuestas) for p in preguntas)
    lineas.append(f"| **Total** | {len(preguntas)} preguntas | **{total}** |")
    por_col = Counter()
    for p in preguntas:
        por_col[p.colectivo] += len(p.respuestas)
    lineas += ["", "Por colectivo: " + ", ".join(f"{c} {n}" for c, n in sorted(por_col.items())), "",
               "No se cargan (piden un nombre, no una opinión; solo sirven para atribuir valoraciones, §7.2):", ""]
    lineas += [f"- {d.cuestionario}: «{d.texto}» ({d.n} respuestas)" for d in descartadas]
    return lineas


def cargar(conn, preguntas) -> None:
    azar = random.SystemRandom()
    with conn.cursor() as cur:
        cur.execute("select id from public.curso where nombre = %s", (CURSO,))
        fila = cur.fetchone()
        if not fila:
            sys.exit(f"No está cargado {CURSO}: ejecuta antes etl/cargar_2526.py")
        curso = fila[0]
        cur.execute("""delete from public.pregunta_abierta pa using public.cuestionario c
                       where c.id = pa.cuestionario_id and c.curso_id = %s""", (curso,))
        cur.execute("select codigo, id from public.cuestionario where curso_id = %s", (curso,))
        cuest = dict(cur.fetchall())
        cur.execute("select nombre, id from public.grupo where curso_id = %s", (curso,))
        grupos = dict(cur.fetchall())
        filas = []
        for p in preguntas:
            if p.cuestionario not in cuest:
                sys.exit(f"Falta el cuestionario {p.cuestionario} en la base de datos")
            cur.execute("""insert into public.pregunta_abierta (cuestionario_id, orden, codigo, texto, nota)
                           values (%s, %s, %s, %s, %s) returning id""",
                        (cuest[p.cuestionario], p.orden, p.codigo, p.texto, p.nota))
            pid = cur.fetchone()[0]
            for r in p.respuestas:
                if r.grupo and r.grupo not in grupos:
                    sys.exit(f"{p.cuestionario}: grupo {r.grupo} sin cargar")
                filas.append((pid, grupos.get(r.grupo), sorted(r.etapas), r.docente, r.antiguedad, r.texto))
        azar.shuffle(filas)
        cur.executemany("""insert into privado.respuesta_abierta (pregunta_id, grupo_id, etapas, docente, antiguedad, texto)
                           values (%s, %s, %s, %s, %s, %s)""", filas)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ensayo", action="store_true", help="solo el recuento, sin cargar")
    ap.add_argument("--remoto", action="store_true", help="permite cargar en una base que no es la local")
    args = ap.parse_args()

    preguntas, descartadas = extraer(RAIZ / "datos_locales/fuentes")
    lineas = resumen(preguntas, descartadas)
    print("\n".join(lineas))
    if args.ensayo:
        return

    import psycopg
    with psycopg.connect(url_bd(args.remoto)) as conn:
        cargar(conn, preguntas)
        conn.commit()
    informe = RAIZ / "datos_locales/informes" / f"carga_abiertas_{CURSO.replace('/', '')}_{datetime.now():%Y-%m-%d_%H%M}.md"
    informe.parent.mkdir(parents=True, exist_ok=True)
    informe.write_text(f"# Carga de las respuestas abiertas de {CURSO}\n\n{datetime.now():%d/%m/%Y %H:%M}. Solo cifras.\n\n"
                       + "\n".join(lineas) + "\n")
    print(f"\nCargado. Informe (solo cifras): {informe.relative_to(RAIZ)}")


if __name__ == "__main__":
    main()
