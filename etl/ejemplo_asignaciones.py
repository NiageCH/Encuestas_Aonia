"""Genera un Excel de asignación con DOCENTES INVENTADOS, con el formato de la plantilla, para
construir y probar la vista de profesor mientras llega el Excel del colegio.

Uso:
    .venv/bin/python etl/ejemplo_asignaciones.py
    .venv/bin/python etl/cargar_asignaciones.py datos_locales/asignacion_ejemplo_2526.xlsx

El fichero se guarda en datos_locales/ (fuera de git). Los nombres son ficticios («Docente
01», «Ejemplo») y los correos acaban en @ejemplo.test. Al cargar el Excel real, se sustituyen.
Cubre cada asignatura y grupo con respuestas: un docente por asignatura y nivel, con un caso
de codocencia y alguno con varias asignaturas.
"""

from __future__ import annotations

import sys
from collections import defaultdict
from pathlib import Path

from openpyxl import load_workbook

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "etl"))
from cargar_2526 import url_bd  # noqa: E402

CURSO = "2025/26"
DEPARTAMENTOS = [
    ("matem", "Matemáticas"), ("ciencia", "Ciencias"), ("física", "Ciencias"), ("química", "Ciencias"),
    ("biolog", "Ciencias"), ("anatom", "Ciencias"), ("lengua española", "Lengua Española y Literatura"),
    ("literatura", "Lengua Española y Literatura"), ("español", "Lengua Española y Literatura"),
    ("inglés", "Inglés y Adquisición de Lenguas"), ("francés", "Inglés y Adquisición de Lenguas"),
    ("alemán", "Inglés y Adquisición de Lenguas"), ("chino", "Inglés y Adquisición de Lenguas"),
    ("árabe", "Inglés y Adquisición de Lenguas"), ("individuos", "Individuos y Sociedades"),
    ("historia", "Individuos y Sociedades"), ("geograf", "Individuos y Sociedades"), ("econom", "Individuos y Sociedades"),
    ("artes", "Artes Visuales y Diseño"), ("diseño", "Artes Visuales y Diseño"), ("dibujo", "Artes Visuales y Diseño"),
    ("música", "Artes Escénicas"), ("dramati", "Artes Escénicas"), ("educación física", "Educación Física"),
]


def departamento(asig: str) -> str:
    a = asig.lower()
    return next((d for k, d in DEPARTAMENTOS if k in a), "Otros")


def main() -> None:
    import psycopg
    with psycopg.connect(url_bd(False)) as conn:
        pares = conn.execute("""
            select distinct g.nivel, g.nombre, a.nombre
            from privado.respuesta_item i
            join privado.respuesta r on r.id = i.respuesta_id
            join public.grupo g on g.id = r.grupo_id
            join public.asignatura a on a.id = i.asignatura_id
            join public.curso c on c.id = a.curso_id
            where c.nombre = %s and i.valor is not null
            order by 1, 2, 3""", (CURSO,)).fetchall()

    # Un docente por asignatura y nivel.
    por_docente: dict[tuple[str, str], list[str]] = defaultdict(list)
    for nivel, grupo, asig in pares:
        por_docente[(asig, nivel)].append(grupo)

    libro = load_workbook(RAIZ / "etl" / "plantillas" / "asignacion_docente_2526.xlsx")
    hoja = libro["Asignación"]
    fila = 2
    for n, ((asig, _nivel), grupos) in enumerate(sorted(por_docente.items()), start=1):
        for g in grupos:
            hoja.append([CURSO, g, asig, "Ejemplo", f"Docente {n:02d}", f"docente{n:02d}@ejemplo.test", departamento(asig)])
            fila += 1
    # Codocencia: el primer grupo del primer docente lo comparte otro docente de ejemplo.
    primero = sorted(por_docente.items())[0]
    hoja.append([CURSO, primero[1][0], primero[0][0], "Ejemplo", "Docente Codocencia", "codocencia@ejemplo.test",
                 departamento(primero[0][0])])

    destino = RAIZ / "datos_locales" / "asignacion_ejemplo_2526.xlsx"
    libro.save(destino)
    print(f"{destino.relative_to(RAIZ)}: {len(por_docente)} docentes de ejemplo, {hoja.max_row - 1} filas")


if __name__ == "__main__":
    main()
