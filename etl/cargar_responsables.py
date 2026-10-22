"""Carga los jefes de departamento y los responsables del Equipo de Individuación (§4, cargo).

Uso:
    .venv/bin/python etl/cargar_responsables.py [RUTA] [--remoto]

Lee datos_locales/responsables_2526.xlsx (fuera de git), hojas «Jefes de departamento»
(Departamento, Jefe/a, Correo) y «Equipo de Individuación» (Cargo, Ámbito, Persona, Correo).
Cada persona se identifica por su correo; si no está en la asignación de profesores, se crea.
Repetible: sustituye los cargos de jefe del curso.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "etl"))
from cargar_2526 import CURSO, url_bd  # noqa: E402
from departamentos_2526 import OFICIALES  # noqa: E402

ORIGEN = RAIZ / "datos_locales" / "responsables_2526.xlsx"
TRAMOS = {"Infantil": "infantil", "Y1-Y5": "y1_y5", "Y6-Y9": "y6_y9", "Y10-Y12": "y10_y12"}


def filas(libro, hoja: str) -> list[dict]:
    datos = list(libro[hoja].iter_rows(values_only=True))
    cab = [str(c or "").strip() for c in datos[0]]
    return [{c: (str(v).strip() if v is not None else "") for c, v in zip(cab, f)} for f in datos[1:] if any(f)]


def partir(completo: str) -> tuple[str, str]:
    partes = completo.split()
    return (partes[0], " ".join(partes[1:])) if len(partes) > 1 else (completo, "")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ruta", type=Path, nargs="?", default=ORIGEN)
    ap.add_argument("--remoto", action="store_true")
    args = ap.parse_args()

    import openpyxl
    import psycopg
    libro = openpyxl.load_workbook(args.ruta, read_only=True, data_only=True)
    jefes = filas(libro, "Jefes de departamento")
    equipo = filas(libro, "Equipo de Individuación")
    for j in jefes:
        if j["Departamento"] not in OFICIALES:
            sys.exit(f"Departamento no oficial: {j['Departamento']!r}")
    for e in equipo:
        if e["Ámbito"] not in TRAMOS:
            sys.exit(f"Ámbito del Equipo de Individuación no válido: {e['Ámbito']!r}")

    with psycopg.connect(url_bd(args.remoto)) as conn, conn.cursor() as cur:
        cur.execute("select id from public.curso where nombre = %s", (CURSO,))
        curso = cur.fetchone()[0]
        cur.execute("delete from public.cargo where curso_id = %s and tipo in ('jefe_departamento', 'jefe_equipo')", (curso,))

        def persona(completo: str, correo: str) -> int:
            nombre, apellidos = partir(completo)
            # Si ya existe (por la asignación), se conservan su nombre y apellidos.
            cur.execute("""insert into public.persona_responsable (nombre, apellidos, correo) values (%s, %s, lower(%s))
                           on conflict (correo) do update set correo = excluded.correo returning id""",
                        (nombre, apellidos, correo))
            return cur.fetchone()[0]

        for j in jefes:
            cur.execute("insert into public.cargo (persona_id, curso_id, tipo, ambito) values (%s, %s, 'jefe_departamento', %s)",
                        (persona(j["Jefe/a"], j["Correo"]), curso, j["Departamento"]))
        for e in equipo:
            cur.execute("insert into public.cargo (persona_id, curso_id, tipo, ambito) values (%s, %s, 'jefe_equipo', %s)",
                        (persona(e["Persona"], e["Correo"]), curso, TRAMOS[e["Ámbito"]]))
        conn.commit()
    personas = len({j["Correo"].lower() for j in jefes})
    print(f"Cargados {len(jefes)} cargos de jefe de departamento ({personas} personas: un cargo por departamento oficial) "
          f"y {len(equipo)} del Equipo de Individuación.")


if __name__ == "__main__":
    main()
