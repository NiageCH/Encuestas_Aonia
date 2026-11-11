"""Carga qué preguntas van en los informes de tutoría y de servicios de 2025/26 (etl/informes_2526.py).

Uso:
    .venv/bin/python etl/cargar_informes_2526.py [--remoto]

Después de cargar_2526.py. Repetible: los servicios se conservan por su código (y con ellos sus responsables, que
mantiene administración desde la aplicación); sus preguntas y las de tutoría se sustituyen.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "etl"))
from cargar_2526 import CURSO, url_bd  # noqa: E402
from informes_2526 import SERVICIOS, TUTORIA_COLEGIO, TUTORIA_GRUPO  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--remoto", action="store_true")
    args = ap.parse_args()

    import psycopg
    with psycopg.connect(url_bd(args.remoto)) as conn, conn.cursor() as cur:
        cur.execute("select id from public.curso where nombre = %s", (CURSO,))
        fila = cur.fetchone()
        if not fila:
            sys.exit(f"No hay curso {CURSO}: carga antes las encuestas (cargar_2526.py).")
        curso = fila[0]

        # Cada código tiene que estar en algún cuestionario del curso.
        codigos = TUTORIA_GRUPO + TUTORIA_COLEGIO + [c for _, _, p, e in SERVICIOS for c in p + e]
        cur.execute("""select p.codigo_diccionario, p.id from public.pregunta p
                       where p.codigo_diccionario = any(%s) and exists (
                         select 1 from public.pregunta_cuestionario pc join public.cuestionario c on c.id = pc.cuestionario_id
                         where pc.pregunta_id = p.id and c.curso_id = %s)""", (codigos, curso))
        ids = dict(cur.fetchall())
        faltan = sorted(set(codigos) - set(ids))
        if faltan:
            sys.exit("Preguntas que no están en las encuestas del curso:\n  " + "\n  ".join(faltan))

        cur.execute("delete from public.tutoria_pregunta where curso_id = %s", (curso,))
        for orden, c in enumerate(TUTORIA_GRUPO, 1):
            cur.execute("insert into public.tutoria_pregunta (curso_id, pregunta_id, ambito, orden) values (%s, %s, 'grupo', %s)",
                        (curso, ids[c], orden))
        for orden, c in enumerate(TUTORIA_COLEGIO, 1):
            cur.execute("insert into public.tutoria_pregunta (curso_id, pregunta_id, ambito, orden) values (%s, %s, 'colegio', %s)",
                        (curso, ids[c], orden))

        for orden, (codigo, nombre, principales, propias) in enumerate(SERVICIOS, 1):
            cur.execute("""insert into public.servicio (curso_id, codigo, nombre, orden) values (%s, %s, %s, %s)
                           on conflict (curso_id, codigo) do update set nombre = excluded.nombre, orden = excluded.orden
                           returning id""", (curso, codigo, nombre, orden))
            sid = cur.fetchone()[0]
            cur.execute("delete from public.servicio_pregunta where servicio_id = %s", (sid,))
            for i, c in enumerate(principales, 1):
                cur.execute("insert into public.servicio_pregunta (servicio_id, pregunta_id, principal, orden) values (%s, %s, true, %s)",
                            (sid, ids[c], i))
            for i, c in enumerate(propias, 1):
                cur.execute("insert into public.servicio_pregunta (servicio_id, pregunta_id, principal, orden) values (%s, %s, false, %s)",
                            (sid, ids[c], i))

        cur.execute("""select s.codigo, exists (select 1 from public.responsable_servicio r where r.servicio_id = s.id)
                       from public.servicio s where s.curso_id = %s and not s.codigo = any(%s)""",
                    (curso, [s[0] for s in SERVICIOS]))
        sobran = cur.fetchall()
        conn.commit()
    print(f"Tutoría: {len(TUTORIA_GRUPO)} preguntas del alumnado y {len(TUTORIA_COLEGIO)} de referencia del Colegio. "
          f"Servicios: {len(SERVICIOS)}.")
    for codigo, con_responsable in sobran:
        print(f"Aviso: el servicio «{codigo}» ya no está en etl/informes_2526.py"
              f"{' y tiene responsable' if con_responsable else ''}; no se ha borrado.")


if __name__ == "__main__":
    main()
