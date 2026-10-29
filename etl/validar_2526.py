"""Validación de la carga 2025/26 contra los agregados verificados del prototipo.

Uso:
    .venv/bin/python etl/validar_2526.py            # base de datos local
    .venv/bin/python etl/validar_2526.py --remoto   # la de DATABASE_URL (nube); informe aparte

Consulta las RPC reales (como un usuario de dirección temporal, dentro de una transacción
que se deshace al final) y compara con datos_locales/referencia_agregados_2526.json:
  1. tabla de control (n, satisfacción general, profesorado, recomendación y NPS);
  2. pregunta por pregunta (n, media y distribución);
  3. asignaturas y grupos.
Criterio: recuentos exactos, medias con tolerancia de ±0,01 y NPS exacto (entero).

Los valores de referencia no se copian a este fichero: se leen del JSON, que está fuera de
git. El resultado se guarda en datos_locales/informes/validacion_2526.md.
"""

from __future__ import annotations

import json
import sys
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path
from typing import Dict, List, Optional, Tuple

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "etl"))

from cargar_2526 import url_bd  # noqa: E402
from cuestionarios_2526 import CURSO, convertir_todo  # noqa: E402
from encuesta_facil import slug  # noqa: E402

USUARIO = "00000000-0000-0000-0000-0000000000f1"
TOLERANCIA = 0.01

ALUMNOS = {"ALU_Y2Y5": "PEP", "ALU_Y6Y9": "PAI_Y6Y9", "ALU_Y6Y10": "PAI_Y6Y10",
           "ALU_Y10": "PAI_Y10", "ALU_Y11": "BI_Y11", "ALU_Y12": "BI_Y12"}

# Nombre de dimensión del prototipo -> código de bloque de la carga
BLOQUES_ALUMNOS = {
    "Profesorado (todas las asignaturas)": "profesorado", "Perfil IB": "perfil_ib",
    "Aprendizaje y convivencia": "aprendizaje_convivencia", "Servicios del colegio": "servicios",
    "Mindfulness": "mindfulness", "Unidades de indagación": "unidades_indagacion", "Programa TKS": "tks",
    "Encuentros con emprendedores": "encuentros", "Narración e improvisación": "narracion",
    "Pasiones": "pasiones", "Ignite!": "ignite", "Eureka!": "eureka", "Autoevaluación IB": "autoevaluacion_ib",
}
BLOQUES_PERSONAL = {"ib": "perfil_ib"}


def redondear(x, decimales: int) -> Optional[Decimal]:
    if x is None:
        return None
    return Decimal(str(x)).quantize(Decimal(1).scaleb(-decimales), rounding=ROUND_HALF_UP)


def fmt(x, decimales=2) -> str:
    if x is None:
        return "·"
    return str(redondear(x, decimales)).replace(".", ",")


def fmt_nps(x) -> str:
    if x is None:
        return "·"
    v = int(redondear(x, 0))
    return f"+{v}" if v > 0 else ("−" + str(-v) if v < 0 else "0")


def rec_de_distribucion(dist: List[int]) -> Tuple[int, float, float]:
    """Distribución del prototipo -> (n, media, NPS). Con 11 posiciones el índice es el valor
    (0 a 10); con 10, el valor es índice + 1 (1 a 10)."""
    base = 0 if len(dist) == 11 else 1
    n = sum(dist)
    media = sum((i + base) * c for i, c in enumerate(dist)) / n
    prom = sum(c for i, c in enumerate(dist) if i + base >= 9)
    det = sum(c for i, c in enumerate(dist) if i + base <= 6)
    return n, media, 100.0 * (prom - det) / n


def excluidas_personal() -> Tuple[int, Dict[str, List[int]], List[int]]:
    """Lee Empleado_2526.csv sin pasar por la ETL y devuelve las respuestas de quienes no
    indican si son docentes o su antigüedad: (número de filas, valores por texto de ítem,
    valores de recomendación). Sirven para ajustar los valores de control del prototipo,
    que sí las incluía."""
    import csv
    from cuestionarios_2526 import ESCALA_FRECUENCIA
    from encuesta_facil import normalizar_texto
    filas = list(csv.reader((RAIZ / "datos_locales" / "fuentes" / "Empleado_2526.csv").open(encoding="utf-8-sig", newline="")))
    q, o, datos = filas[3], filas[4], filas[5:]
    c_doc = next(j for j, t in enumerate(q) if t.startswith("¿Es personal docente"))
    c_ant = next(j for j, t in enumerate(q) if "primer año trabajando" in t)
    c_rec = next(j for j, t in enumerate(q) if "recomendaría el Colegio como centro de trabajo" in t)
    c_ib = next(j for j, t in enumerate(q) if "perfil de la comunidad de aprendizaje" in t)
    excl = [r for r in datos if not r[c_doc].strip() or not r[c_ant].strip()]
    valores: Dict[str, List[int]] = {}
    for j, sub in enumerate(o):
        if sub == "Valor":
            clave = normalizar_texto(o[j + 1]).lower()
            valores.setdefault(clave, []).extend(int(r[j]) for r in excl if r[j].strip() and r[j + 1].strip() != "NS/NC")
    for j in range(c_ib, c_ib + 10):
        clave = normalizar_texto(o[j]).lower()
        valores.setdefault(clave, []).extend(ESCALA_FRECUENCIA[r[j].strip()] for r in excl if r[j].strip() in ESCALA_FRECUENCIA)
    rec = [int(r[c_rec]) for r in excl if r[c_rec].strip()]
    return len(excl), valores, rec


def quitar(dist: List[int], valores: List[int], base: int = 1) -> List[int]:
    d = list(dist)
    for v in valores:
        d[v - base] -= 1
    return d


class Rpc:
    def __init__(self, cur) -> None:
        self.cur = cur

    def __call__(self, filtro: dict, metrica: dict, dims: Optional[List[str]] = None) -> dict:
        with self.cur.connection.transaction():   # punto de guardado: un error no aborta lo demás
            self.cur.execute("select public.resultados(%s::jsonb, %s::jsonb, %s::text[])",
                             (json.dumps({"curso": CURSO, **filtro}), json.dumps(metrica), dims or []))
            return self.cur.fetchone()[0]


def iguales_media(a, b) -> bool:
    return a is not None and b is not None and abs(float(a) - float(b)) <= TOLERANCIA + 1e-9


def marca(ok: bool) -> str:
    return "✅" if ok else "❌"


def main() -> None:
    import argparse
    import psycopg
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--remoto", action="store_true", help="valida la base de DATABASE_URL (la nube); no escribe nada")
    args = ap.parse_args()

    ref = json.loads((RAIZ / "datos_locales" / "referencia_agregados_2526.json").read_text())
    _, cuestionarios = convertir_todo(RAIZ / "datos_locales" / "fuentes")
    origen = {c.codigo: c for c in cuestionarios if c.idioma == "es"}
    salida: List[str] = [f"# Validación de la carga {CURSO}", "",
                         "Comparación entre los agregados verificados del prototipo (control) y lo que devuelven las RPC "
                         "tras la carga (cargado). Medias con tolerancia de ±0,01; recuentos y NPS exactos.", ""]
    fallos_control = 0
    brechas: List[tuple] = []
    notas_grupo: List[str] = []
    n_excl, excl_items, excl_rec = excluidas_personal()

    with psycopg.connect(url_bd(args.remoto)) as conn, conn.cursor() as cur:
        # Media de profesorado por grupo con la fórmula del prototipo (asignaturas con 5 o más
        # personas, ponderadas por personas), calculada como postgres sobre los datos cargados.
        cur.execute("""
            with x as (select c.codigo, g.nombre grupo, a.nombre asig, count(distinct r.id) n, avg(i.valor) m
                       from privado.respuesta_item i join privado.respuesta r on r.id = i.respuesta_id
                       join public.cuestionario c on c.id = r.cuestionario_id join public.grupo g on g.id = r.grupo_id
                       join public.asignatura a on a.id = i.asignatura_id
                       join public.curso cu on cu.id = c.curso_id
                       where cu.nombre = %s and i.valor is not null group by 1, 2, 3)
            select codigo, grupo, sum(n * m) / sum(n) from x where n >= 5 group by 1, 2""", (CURSO,))
        prof_grupo_prototipo = {(c, g): float(v) for c, g, v in cur.fetchall()}
        cur.execute("insert into auth.users (id, email, aud, role) values (%s, 'validacion@local', 'authenticated', 'authenticated')", (USUARIO,))
        cur.execute("insert into public.usuario_perfil (id, nombre, rol) values (%s, 'Validación', 'direccion')", (USUARIO,))
        cur.execute("select set_config('request.jwt.claims', %s, true)",
                    (json.dumps({"sub": USUARIO, "role": "authenticated", "aal": "aal1"}),))
        # El prototipo aplica el mínimo de 5 y la complementaria: se compara con ese mismo criterio, el de la versión docente
        # y la coordinación. Dirección ve además lo de menos de 5 (especificación §5.0), que el prototipo no tiene.
        cur.execute("set local encuestas.version_docente = 'on'")
        cur.execute("set local role authenticated")
        rpc = Rpc(cur)

        # 1. Tabla de control --------------------------------------------------------------
        salida += ["## 1. Tabla de control", "",
                   "| Conjunto | Filas en el fichero (abandonadas) | n control | n cargado | Satisfacción general control | cargado | "
                   "Profesorado control | cargado | Recomendación control (n · media · NPS) | cargado | |",
                   "|---|---|---|---|---|---|---|---|---|---|---|"]
        for codigo, clave in ALUMNOS.items():
            a = ref["alumnos_familias"]["alumnos"][clave]
            t = a["seg"]["total"]
            f = {"colectivo": "alumnos", "cuestionario": codigo}
            n = rpc(f, {"tipo": "personas"})["total"]
            sat = rpc(f, {"tipo": "bloque", "codigo": "satisfaccion_general"})["total"]
            prof = rpc(f, {"tipo": "bloque", "codigo": "profesorado"})["total"]
            rec = rpc(f, {"tipo": "recomendacion"})["total"]
            rn, rm, rnps = rec_de_distribucion(t["rec"])
            # Profesorado: control = media agrupada de las distribuciones de los ítems del prototipo
            # (§3). El prototipo publicó otra fórmula (media de asignaturas ponderada por personas).
            dists = [t["it"][k][3] for k, it in enumerate(a["items"]) if it[0] == 0 and t["it"][k][3]]
            prof_ref = sum((v + 1) * c for d_ in dists for v, c in enumerate(d_)) / sum(sum(d_) for d_ in dists)
            brechas.append((a["title"], t["dm"][0][1], prof_ref, prof["media"]))
            ok = (sat["n_personas"] == t["sat"][0] and iguales_media(sat["media"], t["sat"][1])
                  and iguales_media(prof["media"], prof_ref)
                  and rec["n"] == rn == t["recn"] and iguales_media(rec["media"], rm)
                  and int(redondear(rec["nps"], 0)) == int(redondear(rnps, 0)))
            fallos_control += not ok
            o = origen[codigo]
            salida.append(
                f"| {a['title']} | {o.filas} ({o.abandonadas}) | {t['n']} | {n['n']} | {t['sat'][0]} · {fmt(t['sat'][1])} | "
                f"{sat['n_personas']} · {fmt(sat['media'])} | {fmt(prof_ref)} | {fmt(prof['media'])} | "
                f"{rn} · {fmt(rm)} · {fmt_nps(rnps)} | {rec['n']} · {fmt(rec['media'])} · {fmt_nps(rec['nps'])} | {marca(ok)} |")

        fam = ref["alumnos_familias"]["familias"]
        tf = fam["seg"]["total"]
        f = {"colectivo": "familias"}
        n = rpc(f, {"tipo": "personas"})["total"]
        gen = rpc(f, {"tipo": "bloque", "codigo": "general"})["total"]
        rec = rpc(f, {"tipo": "recomendacion"})["total"]
        rn, rm, rnps = rec_de_distribucion(tf["rec"])
        # Media agrupada del bloque a partir de las distribuciones de sus ítems.
        idx_general = [d[0] for d in fam["dims"]].index("general")
        dist_gen = [r[3] for (dim, _), r in zip(fam["items"], tf["it"]) if dim == idx_general]
        gen_ref = sum((v + 1) * c for d_ in dist_gen for v, c in enumerate(d_)) / sum(sum(d_) for d_ in dist_gen)
        ok = iguales_media(gen["media"], gen_ref) and rec["n"] == rn \
            and iguales_media(rec["media"], rm) and int(redondear(rec["nps"], 0)) == int(redondear(rnps, 0))
        fallos_control += not ok
        o = origen["FAM"]
        salida.append(
            f"| Familias (valoración general del centro) | {o.filas} ({o.abandonadas}) | {tf['n']} | {n['n']} | "
            f"{fmt(gen_ref)} | {fmt(gen['media'])} | | | {rn} · {fmt(rm)} · {fmt_nps(rnps)} | "
            f"{rec['n']} · {fmt(rec['media'])} · {fmt_nps(rec['nps'])} | {marca(ok)} |")

        per = ref["personal_es"]
        tp = per["seg"]["total"]
        f = {"colectivo": "personal"}
        n = rpc(f, {"tipo": "personas"})["total"]
        rec = rpc(f, {"tipo": "recomendacion"})["total"]
        rn, rm, rnps = rec_de_distribucion(quitar(tp["rec"], excl_rec))
        ok = rec["n"] == rn and iguales_media(rec["media"], rm) and int(redondear(rec["nps"], 0)) == int(redondear(rnps, 0))
        fallos_control += not ok
        o = origen["PER"]
        salida.append(
            f"| Personal (solo español) | {o.filas} ({o.abandonadas}) | {tp['n'] - n_excl} | {n['n']} | | | | | "
            f"{rn} · {fmt(rm)} · {fmt_nps(rnps)} | {rec['n']} · {fmt(rec['media'])} · {fmt_nps(rec['nps'])} | {marca(ok)} |")

        salida += ["", "Notas:",
                   "- **n control** = filas del fichero (el prototipo contaba todas). **n cargado** = personas con al menos una "
                   "valoración válida u opción marcada (regla acordada). La diferencia son filas sin ninguna respuesta válida.",
                   "- La satisfacción general de familias es la media agrupada del bloque «Valoración general del centro».",
                   "- **Profesorado (control):** media agrupada de las distribuciones de los ítems del prototipo (§3). "
                   "El prototipo publicó la media de asignaturas ponderada por personas; ver la tabla de brechas.",
                   f"- **Personal (control):** valores del prototipo sin la(s) {n_excl} respuesta(s) que no indican segmento, "
                   "leídas directamente del fichero original (excluidas de personal por decisión del 14/10/2026).", "",
                   "### Brecha entre fórmulas de profesorado", "",
                   "| Conjunto | Publicada por el prototipo (asignaturas ponderadas) | Agrupada desde sus ítems (§3) | Cargada | Brecha |",
                   "|---|---|---|---|---|"]
        for titulo, publicada, agrupada, cargada in brechas:
            salida.append(f"| {titulo} | {fmt(publicada)} | {fmt(agrupada, 4)} | {fmt(cargada, 4)} | {fmt(abs(agrupada - publicada), 4)} |")
        salida.append("")

        # 2. Pregunta por pregunta -------------------------------------------------------
        salida += ["## 2. Pregunta por pregunta", "",
                   "| Conjunto | Preguntas del prototipo | Cuadran (n, media y distribución) | No cuadran |", "|---|---|---|---|"]
        detalles: List[str] = []

        def comparar_items(nombre: str, filtro: dict, items: list, it_ref: list, codigo_de) -> None:
            agrupado: Dict[str, list] = {}
            for (dim, texto), r in zip(items, it_ref):
                codigo = codigo_de(dim, texto)
                if codigo is None:
                    continue
                n_, media_, nsnc_, dist_ = r
                n_, dist_ = n_ or 0, dist_ or [0] * 6   # ítems sin respuestas en el prototipo
                if codigo.startswith("alu.autoevaluacion_ib."):
                    # El prototipo contó como valoración el 4, que en el fichero es NS/NC (escala
                    # real de 1 a 3): se compara con la lectura correcta.
                    dist_ = dist_[:3] + [0] * (len(dist_) - 3)
                    n_ = sum(dist_)
                prev = agrupado.get(codigo)
                if prev is None:
                    agrupado[codigo] = [texto, n_, list(dist_)]
                else:   # ítems duplicados del prototipo: se suman
                    prev[1] += n_
                    prev[2] = [x + y for x, y in zip(prev[2], dist_)]
            buenos, malos = 0, []
            for codigo, (texto, n_, dist_) in agrupado.items():
                try:
                    r = rpc(filtro, {"tipo": "pregunta", "codigo": codigo})["total"]
                except psycopg.Error as e:   # pregunta inexistente
                    malos.append(f"`{codigo}`: no existe en la carga ({e.__class__.__name__})")
                    continue
                media_ref = sum((v + 1) * c for v, c in enumerate(dist_)) / sum(dist_) if sum(dist_) else None
                if r.get("suprimido"):
                    ok = n_ < 5
                    desc = f"suprimida en la carga; prototipo n {n_}"
                else:
                    dist = [r["distribucion"][k] for k in sorted(r["distribucion"], key=int)]
                    dist_ref = dist_[:len(dist)] + [0] * max(0, len(dist) - len(dist_))
                    ok = r["n"] == n_ and (n_ == 0 or iguales_media(r["media"], media_ref)) and dist == dist_ref
                    desc = (f"prototipo n {n_} · media {fmt(media_ref)} · {dist_} | carga n {r['n']} · "
                            f"media {fmt(r['media'])} · {dist}")
                if ok:
                    buenos += 1
                else:
                    malos.append(f"{texto[:70]}: {desc}")
            salida.append(f"| {nombre} | {len(agrupado)} | {buenos} | {len(malos)} |")
            if malos:
                detalles.append(f"**{nombre}**")
                detalles.extend(f"- {m}" for m in malos)
                detalles.append("")

        for codigo, clave in ALUMNOS.items():
            a = ref["alumnos_familias"]["alumnos"][clave]
            dims = a["dims"]

            def codigo_alumnos(dim, texto, dims=dims):
                bloque = BLOQUES_ALUMNOS[dims[dim][1]]
                return f"alu.{bloque}.{slug(texto, 120)}"
            comparar_items(a["title"], {"colectivo": "alumnos", "cuestionario": codigo}, a["items"], a["seg"]["total"]["it"], codigo_alumnos)

        comparar_items("Familias", {"colectivo": "familias"}, fam["items"], tf["it"],
                       lambda dim, texto: f"fam.{fam['dims'][dim][0]}.{slug(texto, 120)}")
        from encuesta_facil import normalizar_texto
        it_personal = []
        for (dim, texto), r in zip(per["items"], tp["it"]):
            quitar_ = excl_items.get(normalizar_texto(texto).lower(), [])
            n_, media_, nsnc_, dist_ = r
            it_personal.append([(n_ or 0) - len(quitar_), media_, nsnc_, quitar(dist_ or [0] * 6, quitar_)])
        comparar_items("Personal (sin respuestas excluidas)", {"colectivo": "personal"}, per["items"], it_personal,
                       lambda dim, texto: f"per.{BLOQUES_PERSONAL.get(dim, dim)}.{slug(texto, 120)}")

        # 3. Asignaturas, grupos, etapas y segmentos ---------------------------------------
        salida += ["", "## 3. Asignaturas, grupos, etapas y segmentos", "",
                   "| Conjunto | Comprobaciones | Cuadran | No cuadran |", "|---|---|---|---|"]
        for codigo, clave in ALUMNOS.items():
            a = ref["alumnos_familias"]["alumnos"][clave]
            t = a["seg"]["total"]
            f = {"colectivo": "alumnos", "cuestionario": codigo}
            buenos, malos = 0, []
            partes = {p["clave"]["asignatura"]: p for p in rpc(f, {"tipo": "bloque", "codigo": "profesorado"}, ["asignatura"])["partes"]}
            for nombre, (n_, m_) in zip(a["asig"], t["asig"]):
                p = partes.get(nombre)
                if p is None:
                    ok, desc = n_ == 0, f"no aparece en la carga (prototipo n {n_})"
                elif p["suprimido"]:
                    ok, desc = n_ < 5 or p["motivo"] == "complementaria", f"oculta ({p['motivo']}); prototipo n {n_}"
                else:
                    ok = p["n"] == n_ and iguales_media(p["media"], m_)
                    desc = f"prototipo {n_} · {fmt(m_)} | carga {p['n']} · {fmt(p['media'])}"
                buenos += ok
                if not ok:
                    malos.append(f"asignatura {nombre}: {desc}")
            grupos_sat = {p["clave"]["grupo"]: p for p in rpc(f, {"tipo": "bloque", "codigo": "satisfaccion_general"}, ["grupo"])["partes"]}
            grupos_prof = {p["clave"]["grupo"]: p for p in rpc(f, {"tipo": "bloque", "codigo": "profesorado"}, ["grupo"])["partes"]}
            for g in a["groups"]:
                s = a["seg"][g]
                # Profesorado del grupo: se comprueba que los datos reproducen la cifra del
                # prototipo con su fórmula; la carga muestra la media de todas las valoraciones
                # del grupo (decisión del 14/10/2026).
                formula = prof_grupo_prototipo.get((codigo, g))
                ok = formula is not None and iguales_media(formula, s["dm"][0][1])
                buenos += ok
                if not ok:
                    malos.append(f"grupo {g}, profesorado con la fórmula del prototipo: {s['dm'][0][1]} / {formula}")
                p = grupos_prof.get(g)
                if p and not p["suprimido"] and not iguales_media(p["media"], s["dm"][0][1]):
                    notas_grupo.append(f"{a['title']}, {g}: prototipo {fmt(s['dm'][0][1])} · carga (todas las valoraciones) {fmt(p['media'])}")
                for etiqueta, ref_val, p in (("satisfacción", s["sat"], grupos_sat.get(g)),):
                    if p is None or ref_val is None:
                        ok, desc = False, "sin dato"
                    elif p["suprimido"]:
                        ok, desc = True, f"oculto ({p['motivo']})"
                    else:
                        ok = (ref_val[0] is None or p["n_personas"] == ref_val[0]) and iguales_media(p["media"], ref_val[1])
                        desc = f"prototipo {ref_val} | carga {p['n_personas']} · {fmt(p['media'])}"
                    buenos += ok
                    if not ok:
                        malos.append(f"grupo {g}, {etiqueta}: {desc}")
            salida.append(f"| {a['title']} | {len(a['asig']) + 2 * len(a['groups'])} | {buenos} | {len(malos)} |")
            if malos:
                detalles.append(f"**{a['title']}: asignaturas y grupos**")
                detalles.extend(f"- {m}" for m in malos)
                detalles.append("")

        etapas = {p["clave"]["etapa"]: p for p in rpc({"colectivo": "familias"}, {"tipo": "personas"}, ["etapa"])["partes"]}
        filas = []
        for clave, etapa in (("infantil", "infantil"), ("primaria", "primaria"), ("pai", "pai"), ("bach", "bachillerato")):
            p = etapas.get(etapa, {})
            filas.append(f"{etapa} {fam['seg'][clave]['n']} / {p.get('n', p.get('motivo', '·'))}")
        salida.append(f"| Familias por etapa (prototipo / carga) | {'; '.join(filas)} | | |")
        segs = []
        for clave, filtro in (("doc_si", {"docente": True}), ("doc_no", {"docente": False}),
                              ("nuevo_si", {"antiguedad": "primer_ano"}), ("nuevo_no", {"antiguedad": "mas_de_un_ano"})):
            t = rpc({"colectivo": "personal", **filtro}, {"tipo": "personas"})["total"]
            segs.append(f"{clave} {per['seg'][clave]['n']} / {t.get('n', t.get('motivo'))}")
        salida.append(f"| Personal por segmento (prototipo, que cuenta todas las filas / carga) | {'; '.join(segs)} | | |")

        salida += ["", "Media de profesorado de un grupo: la carga usa todas las valoraciones del grupo; el prototipo, solo "
                   "las asignaturas con 5 o más personas. Las comprobaciones de arriba validan los datos con la fórmula del "
                   "prototipo. Grupos donde la cifra mostrada cambia:", ""] + [f"- {x}" for x in notas_grupo]
        salida += ["", "## Diferencias", ""] + (detalles or ["Ninguna."])
        conn.rollback()

    texto = "\n".join(salida) + "\n"
    destino = RAIZ / "datos_locales" / "informes" / ("validacion_2526_nube.md" if args.remoto else "validacion_2526.md")
    destino.write_text(texto)
    print(texto)
    print(f"Guardado en {destino.relative_to(RAIZ)}")
    sys.exit(1 if fallos_control else 0)


if __name__ == "__main__":
    main()
