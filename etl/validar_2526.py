"""Validación de la carga 2025/26 contra los agregados verificados del prototipo.

Uso:
    .venv/bin/python etl/validar_2526.py

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
    import psycopg

    ref = json.loads((RAIZ / "datos_locales" / "referencia_agregados_2526.json").read_text())
    _, cuestionarios = convertir_todo(RAIZ / "datos_locales" / "fuentes")
    origen = {c.codigo: c for c in cuestionarios if c.idioma == "es"}
    salida: List[str] = [f"# Validación de la carga {CURSO}", "",
                         "Comparación entre los agregados verificados del prototipo (control) y lo que devuelven las RPC "
                         "tras la carga (cargado). Medias con tolerancia de ±0,01; recuentos y NPS exactos.", ""]
    fallos_control = 0

    with psycopg.connect(url_bd(False)) as conn, conn.cursor() as cur:
        cur.execute("insert into auth.users (id, email, aud, role) values (%s, 'validacion@local', 'authenticated', 'authenticated')", (USUARIO,))
        cur.execute("insert into public.usuario_perfil (id, nombre, rol) values (%s, 'Validación', 'direccion')", (USUARIO,))
        cur.execute("select set_config('request.jwt.claims', %s, true)",
                    (json.dumps({"sub": USUARIO, "role": "authenticated", "aal": "aal1"}),))
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
            ok = (sat["n_personas"] == t["sat"][0] and iguales_media(sat["media"], t["sat"][1])
                  and iguales_media(prof["media"], t["dm"][0][1])
                  and rec["n"] == rn == t["recn"] and iguales_media(rec["media"], rm)
                  and int(redondear(rec["nps"], 0)) == int(redondear(rnps, 0)))
            fallos_control += not ok
            o = origen[codigo]
            salida.append(
                f"| {a['title']} | {o.filas} ({o.abandonadas}) | {t['n']} | {n['n']} | {t['sat'][0]} · {fmt(t['sat'][1])} | "
                f"{sat['n_personas']} · {fmt(sat['media'])} | {fmt(t['dm'][0][1])} | {fmt(prof['media'])} | "
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
        rn, rm, rnps = rec_de_distribucion(tp["rec"])
        ok = rec["n"] == rn and iguales_media(rec["media"], rm) and int(redondear(rec["nps"], 0)) == int(redondear(rnps, 0))
        fallos_control += not ok
        o = origen["PER"]
        salida.append(
            f"| Personal (solo español) | {o.filas} ({o.abandonadas}) | {tp['n']} | {n['n']} | | | | | "
            f"{rn} · {fmt(rm)} · {fmt_nps(rnps)} | {rec['n']} · {fmt(rec['media'])} · {fmt_nps(rec['nps'])} | {marca(ok)} |")

        salida += ["", "Notas:",
                   "- **n control** = filas del fichero (el prototipo contaba todas). **n cargado** = personas con al menos una "
                   "valoración válida u opción marcada (regla acordada). La diferencia son filas sin ninguna respuesta válida.",
                   "- La satisfacción general de familias es la media agrupada del bloque «Valoración general del centro».", ""]

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
        comparar_items("Personal", {"colectivo": "personal"}, per["items"], tp["it"],
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
                for etiqueta, ref_val, p in (("satisfacción", s["sat"], grupos_sat.get(g)),
                                             ("profesorado", [None, s["dm"][0][1]], grupos_prof.get(g))):
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
        salida.append(f"| Personal por segmento (prototipo / carga) | {'; '.join(segs)} | | |")

        salida += ["", "## Diferencias", ""] + (detalles or ["Ninguna."])
        conn.rollback()

    texto = "\n".join(salida) + "\n"
    destino = RAIZ / "datos_locales" / "informes" / "validacion_2526.md"
    destino.write_text(texto)
    print(texto)
    print(f"Guardado en {destino.relative_to(RAIZ)}")
    sys.exit(1 if fallos_control else 0)


if __name__ == "__main__":
    main()
