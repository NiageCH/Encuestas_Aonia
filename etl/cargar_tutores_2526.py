"""Carga el tutor/a de cada grupo de 2025/26 desde la hoja «Tutores» del listado de Alexia (especificación §7.12).

Uso:
    .venv/bin/python etl/cargar_tutores_2526.py [RUTA_ALEXIA] [--remoto] [--ensayo]

Lee datos_locales/fuentes/Grupos_asignaturas_docentes_2025-26.xlsx (fuera de git), columnas Grupo, «Tutor/a» y
«Correo tutor/a». El cotutor/a no se carga: el informe de tutoría va solo al tutor/a (decisión de Mark del 11/11/2026).

Emparejamiento de grupos, el mismo que la asignación de profesores (convertir_alexia_2526.grupo): «Y9-A» es «Y9 A» y
los grupos «.Comp» de Alexia son el grupo de la encuesta con el mismo curso y letra («Y6-B.Comp» es «Y6 B»). Los grupos
de Infantil y de Y1 no tienen encuesta del alumnado y no se cargan.

Cada persona se identifica por su correo; si no está ya (por la asignación), se crea. Repetible: sustituye los
tutores del curso. Con --ensayo solo enseña el emparejamiento (grupos y recuentos, sin nombres) y no toca nada.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "etl"))
from cargar_2526 import CURSO, url_bd  # noqa: E402
from convertir_alexia_2526 import ORIGEN, grupo, partir_nombre  # noqa: E402


def leer(ruta: Path) -> list[dict]:
    import openpyxl
    libro = openpyxl.load_workbook(ruta, read_only=True, data_only=True)
    filas = list(libro["Tutores"].iter_rows(values_only=True))
    cab = [str(c or "").strip() for c in filas[0]]
    for falta in ("Grupo", "Tutor/a", "Correo tutor/a"):
        if falta not in cab:
            sys.exit(f"La hoja «Tutores» no tiene la columna «{falta}».")
    return [{c: (str(v).strip() if v is not None else "") for c, v in zip(cab, f)} for f in filas[1:] if any(f)]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ruta", type=Path, nargs="?", default=ORIGEN)
    ap.add_argument("--remoto", action="store_true")
    ap.add_argument("--ensayo", action="store_true", help="solo el emparejamiento, sin tocar la base de datos")
    args = ap.parse_args()

    filas = leer(args.ruta)
    import psycopg
    with psycopg.connect(url_bd(args.remoto)) as conn, conn.cursor() as cur:
        cur.execute("select id from public.curso where nombre = %s", (CURSO,))
        curso = cur.fetchone()[0]
        cur.execute("""select g.nombre, g.id, exists (select 1 from privado.respuesta r where r.grupo_id = g.id)
                       from public.grupo g where g.curso_id = %s""", (curso,))
        grupos = {n: (i, con) for n, i, con in cur.fetchall()}

        emparejados: dict[str, dict] = {}
        sin_encuesta: list[str] = []
        sin_tutor: list[str] = []
        for f in filas:
            g = grupo(f["Grupo"])
            if g is None or g not in grupos:
                sin_encuesta.append(f["Grupo"])
                continue
            if not f["Correo tutor/a"]:
                sin_tutor.append(g)
                continue
            if g in emparejados:
                sys.exit(f"Dos filas de Alexia van al grupo {g}: {emparejados[g]['Grupo']!r} y {f['Grupo']!r}.")
            emparejados[g] = f
        sin_fila = sorted(n for n, (_, con) in grupos.items() if con and n not in emparejados and n not in sin_tutor)

        print("Emparejamiento (Alexia → encuesta):")
        for g, f in sorted(emparejados.items(), key=lambda x: (int(x[0][1:].split()[0]), x[0])):
            marca = "" if f["Grupo"].replace("-", " ") == g else "   ← " + f["Grupo"]
            print(f"  {g}{marca}")
        print(f"Grupos de Alexia sin encuesta del alumnado (no se cargan): {len(sin_encuesta)} "
              f"({', '.join(sin_encuesta)})")
        if sin_tutor:
            print(f"Grupos sin tutor/a en Alexia: {', '.join(sorted(sin_tutor))}")
        if sin_fila:
            print(f"Grupos con respuestas que no están en la hoja: {', '.join(sin_fila)}")
        if args.ensayo:
            print("Ensayo: no se ha cargado nada.")
            return

        cur.execute("delete from public.tutoria where curso_id = %s", (curso,))
        nuevas = 0
        for g, f in emparejados.items():
            correo = f["Correo tutor/a"].lower()
            cur.execute("select id from public.persona_responsable where lower(correo) = %s", (correo,))
            fila = cur.fetchone()
            if fila:
                pid = fila[0]
            else:
                nombre, apellidos, _ = partir_nombre(f["Tutor/a"], correo)
                cur.execute("insert into public.persona_responsable (nombre, apellidos, correo) values (%s, %s, %s) returning id",
                            (nombre, apellidos, correo))
                pid = cur.fetchone()[0]
                nuevas += 1
            cur.execute("insert into public.tutoria (curso_id, grupo_id, persona_id) values (%s, %s, %s)",
                        (curso, grupos[g][0], pid))
        conn.commit()
    print(f"Cargados {len(emparejados)} tutores ({len({f['Correo tutor/a'].lower() for f in emparejados.values()})} personas, "
          f"{nuevas} que no estaban en la asignación).")


if __name__ == "__main__":
    main()
