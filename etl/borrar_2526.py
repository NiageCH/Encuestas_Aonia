"""Borra todos los datos de encuestas del curso 2025/26 (respuestas, catálogo del curso,
asignaciones, responsables y su atribución), en una sola transacción.

Uso:
    .venv/bin/python etl/borrar_2526.py                       # local: muestra lo que borraría
    .venv/bin/python etl/borrar_2526.py --confirmar           # local: borra
    .venv/bin/python etl/borrar_2526.py --remoto [--confirmar]   # la base de DATABASE_URL (nube)

No toca los usuarios ni sus perfiles, ni el registro de actividad. Las preguntas del
diccionario y las personas solo se borran si ningún otro curso las usa. Después del borrado,
comprueba que no queda nada del curso; si quedara algo, deshace todo.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "etl"))
from cargar_2526 import url_bd  # noqa: E402
from cuestionarios_2526 import CURSO  # noqa: E402

RECUENTO = """
select 'cuestionarios', count(*) from public.cuestionario where curso_id = %(c)s
union all select 'respuestas', count(*) from privado.respuesta r join public.cuestionario q on q.id = r.cuestionario_id where q.curso_id = %(c)s
union all select 'valoraciones', count(*) from privado.respuesta_item i join privado.respuesta r on r.id = i.respuesta_id
          join public.cuestionario q on q.id = r.cuestionario_id where q.curso_id = %(c)s
union all select 'atribuciones', count(*) from privado.respuesta_docente d join privado.respuesta r on r.id = d.respuesta_id
          join public.cuestionario q on q.id = r.cuestionario_id where q.curso_id = %(c)s
union all select 'tramos', count(*) from privado.respuesta_tramo t join privado.respuesta r on r.id = t.respuesta_id
          join public.cuestionario q on q.id = r.cuestionario_id where q.curso_id = %(c)s
union all select 'grupos', count(*) from public.grupo where curso_id = %(c)s
union all select 'asignaturas', count(*) from public.asignatura where curso_id = %(c)s
union all select 'departamentos', count(*) from public.departamento where curso_id = %(c)s
union all select 'asignaciones', count(*) from public.asignacion_docente where curso_id = %(c)s
union all select 'cargos', count(*) from public.cargo where curso_id = %(c)s
union all select 'personas (docentes y responsables)', count(*) from public.persona_responsable
union all select 'preguntas del diccionario', count(*) from public.pregunta
"""


def recuento(cur, curso: int) -> dict:
    cur.execute(RECUENTO, {"c": curso})
    return dict(cur.fetchall())


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--remoto", action="store_true", help="la base de DATABASE_URL (la nube)")
    ap.add_argument("--confirmar", action="store_true", help="borra de verdad (sin esto, solo muestra el recuento)")
    args = ap.parse_args()

    import psycopg
    with psycopg.connect(url_bd(args.remoto)) as conn, conn.cursor() as cur:
        cur.execute("select id from public.curso where nombre = %s", (CURSO,))
        fila = cur.fetchone()
        if not fila:
            print(f"No hay datos del curso {CURSO}.")
            return
        curso = fila[0]
        antes = recuento(cur, curso)
        print(f"Datos del curso {CURSO} en {'la nube' if args.remoto else 'local'}:")
        for k, v in antes.items():
            print(f"  {k:38} {v}")
        if not args.confirmar:
            print("Sin --confirmar no se borra nada.")
            return

        # Las respuestas, sus valoraciones, etapas, tramos y atribuciones caen en cascada.
        cur.execute("delete from public.cuestionario where curso_id = %s", (curso,))
        cur.execute("delete from public.asignacion_docente where curso_id = %s", (curso,))
        cur.execute("delete from public.cargo where curso_id = %s", (curso,))
        cur.execute("""update public.persona_responsable set departamento_id = null
                       where departamento_id in (select id from public.departamento where curso_id = %s)""", (curso,))
        cur.execute("delete from public.departamento where curso_id = %s", (curso,))
        cur.execute("delete from public.grupo where curso_id = %s", (curso,))
        cur.execute("delete from public.asignatura where curso_id = %s", (curso,))
        # Personas y preguntas que ya no usa ningún curso.
        cur.execute("""delete from public.persona_responsable pr
                       where not exists (select 1 from public.asignacion_docente a where a.docente_id = pr.id)
                         and not exists (select 1 from public.cargo c where c.persona_id = pr.id)
                         and not exists (select 1 from privado.respuesta_docente d where d.docente_id = pr.id)""")
        cur.execute("""delete from public.pregunta_comun pc
                       where not exists (select 1 from public.pregunta_cuestionario x where x.pregunta_id = pc.pregunta_id)""")
        cur.execute("""delete from public.pregunta p
                       where not exists (select 1 from public.pregunta_cuestionario x where x.pregunta_id = p.id)""")
        cur.execute("delete from public.curso where id = %s", (curso,))

        cur.execute("select count(*) from public.curso where nombre = %s", (CURSO,))
        queda = cur.fetchone()[0]
        despues = recuento(cur, curso)
        sobrantes = {k: v for k, v in despues.items() if v and not k.startswith(("personas", "preguntas"))}
        if queda or sobrantes:
            conn.rollback()
            sys.exit(f"Ha quedado algo del curso ({sobrantes}); no se ha borrado nada.")
        conn.commit()
        print("Borrado. Quedan en otras temporadas:", {k: v for k, v in despues.items() if v} or "nada")


if __name__ == "__main__":
    main()
