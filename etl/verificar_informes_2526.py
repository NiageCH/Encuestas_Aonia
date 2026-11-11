"""Comprobación independiente de los informes de 2025/26: profesorado, jefaturas de departamento, Equipo de
Individuación, tutoría y servicios, en la versión completa y en la del destinatario (docente, jefatura, tutor/a o
responsable del servicio).

Uso:
    .venv/bin/python etl/verificar_informes_2526.py            # base de datos local
    .venv/bin/python etl/verificar_informes_2526.py --remoto   # la de DATABASE_URL (nube); no escribe nada

Recalcula desde las tablas de respuestas, sin funciones de la plataforma, qué respuestas forman cada clase (propia,
compartida, atribuida por el nombre que escribió el alumnado, optativa) y cada sección, y sus cifras: respuestas,
personas, valoraciones, NS/NC, media y reparto; media global del docente; detalle por pregunta y por clase; medias de
etapa y Colegio (todo el profesorado); reuniones de departamento, media del profesorado de cada jefatura según el
alumnado, Equipo de Individuación por tramos, tutoría (cada grupo, su etapa y la referencia del Colegio; los tutores,
también frente a la hoja «Tutores» de Alexia) y servicios (cada colectivo, en total y por etapa, y el catálogo frente a
etl/informes_2526.py). Pide a la plataforma los mismos informes (como un usuario de Dirección
temporal, en una transacción que se deshace) y compara cifra a cifra. Ejecuta también la tabla «Detalle por pregunta»
del frontend (src/data/tablaProfesor.ts) y las de tutoría y servicios (src/data/tablasResumen.ts), con vite-node,
sobre esos informes.

De lo que la plataforma oculta comprueba que el motivo encaja con el número de respuestas («menos de 5» con menos de 5,
«oculto» con 5 o más, nada visible con menos de 5 fuera de la versión completa, el paso por clase y los tramos). La
supresión complementaria entre tablas no se rehace: se toma de la plataforma qué celdas oculta.

Los informes de la plataforma solo pasan por una carpeta temporal que se borra al terminar. El resultado (solo cifras
y, si las hay, las diferencias) se guarda en datos_locales/informes/verificacion_informes_2526[_nube].md, fuera de git.
Sale con código 1 si hay alguna diferencia.
"""
import argparse
import json
import subprocess
import sys
import tempfile
import time
import uuid
from collections import defaultdict
from decimal import Decimal
from pathlib import Path

import psycopg

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "etl"))
from cargar_2526 import url_bd  # noqa: E402
from cuestionarios_2526 import CURSO  # noqa: E402
from cuenta_tecnica import Uso  # noqa: E402

ap_args = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap_args.add_argument("--remoto", action="store_true", help="comprueba la base de DATABASE_URL (la nube); no escribe nada")
ARGS = ap_args.parse_args()

MIN = 5
TOL = 1e-9
TEMPORAL = tempfile.TemporaryDirectory(prefix="verificacion_informes_")
SALIDA = Path(TEMPORAL.name)

comparadas = defaultdict(int)       # cifras comparadas por apartado
anonimato = defaultdict(int)        # comprobaciones de criterio por apartado
diferencias = []


def cmp(apartado, donde, campo, esperado, plataforma):
    comparadas[apartado] += 1
    if esperado is None or plataforma is None:
        ok = esperado is None and plataforma is None
    elif isinstance(esperado, float) or isinstance(plataforma, (float, Decimal)):
        ok = abs(float(esperado) - float(plataforma)) < TOL
    else:
        ok = esperado == plataforma
    if not ok:
        diferencias.append(f"[{apartado}] {donde} · {campo}: independiente {esperado!r} · plataforma {plataforma!r}")


def regla(apartado, donde, cond, msg):
    anonimato[apartado] += 1
    if not cond:
        diferencias.append(f"[{apartado}] {donde} · CRITERIO: {msg}")


URL_BD = url_bd(ARGS.remoto)
USUARIO = str(uuid.uuid4())
# Cuenta técnica de verificación: alta temporal y baja en el registro de actividad (etl/cuenta_tecnica.py).
USO = Uso(URL_BD, "etl/verificar_informes_2526.py", "nube" if ARGS.remoto else "local").empezar()


class Consultas:
    """Cada consulta va en una transacción corta que siempre se deshace (la nube cierra las transacciones que se
    quedan abiertas sin hacer nada). Con `version`, como un usuario de Dirección temporal que se crea dentro de la
    misma transacción y desaparece con ella, con la versión completa o la del destinatario («docente» o «jefatura»).
    Si se corta la conexión, reconecta y reintenta."""

    def __init__(self):
        self.conn = psycopg.connect(URL_BD)
        self.version = None
        self.filas = []

    def execute(self, sql, params=()):
        for intento in range(5):
            try:
                with self.conn.cursor() as c:
                    if self.version is not None:
                        c.execute("insert into auth.users (id, email, aud, role) values (%s, 'verificacion@local', 'authenticated', 'authenticated')", (USUARIO,))
                        c.execute("insert into public.usuario_perfil (id, nombre, rol) values (%s, 'Cuenta técnica de verificación (Niage)', 'direccion')", (USUARIO,))
                        c.execute("select set_config('request.jwt.claims', %s, true), set_config('encuestas.version_docente', %s, true)",
                                  (json.dumps({"sub": USUARIO, "role": "authenticated", "aal": "aal1"}),
                                   "" if self.version == "completa" else "on"))
                    c.execute(sql, params)
                    self.filas = c.fetchall()
                self.conn.rollback()
                return
            except psycopg.OperationalError as e:
                print(f"Conexión cortada ({str(e).splitlines()[0][:80]}); reintento {intento + 1} de 5", file=sys.stderr)
                try:
                    self.conn.close()
                except Exception:
                    pass
                time.sleep(15 * (intento + 1))
                self.conn = psycopg.connect(URL_BD)
        raise SystemExit("La conexión se corta una y otra vez: no se ha podido terminar la comprobación.")

    def fetchall(self):
        return self.filas

    def fetchone(self):
        return self.filas[0] if self.filas else None


cur = Consultas()
cur.execute("select id from public.curso where nombre = %s", (CURSO,))
CID = cur.fetchone()[0]

# ---------------------------------------------------------------- datos en bruto
cur.execute("select id, codigo, etapa, colectivo from public.cuestionario where curso_id = %s", (CID,))
CUEST = {r[0]: {"codigo": r[1], "etapa": r[2], "colectivo": r[3]} for r in cur.fetchall()}
cur.execute("select id, nombre, etapa from public.grupo where curso_id = %s", (CID,))
GRUPO = {r[0]: {"nombre": r[1], "etapa": r[2]} for r in cur.fetchall()}
cur.execute("select id, nombre from public.asignatura where curso_id = %s", (CID,))
ASIG = {r[0]: r[1] for r in cur.fetchall()}
cur.execute("select id, codigo_diccionario, tipo, escala_min, escala_max from public.pregunta")
PREG = {r[0]: {"codigo": r[1], "tipo": r[2], "min": r[3], "max": r[4]} for r in cur.fetchall()}
PREG_COD = {v["codigo"]: k for k, v in PREG.items()}
cur.execute("""select pc.cuestionario_id, pc.pregunta_id, b.codigo, pc.por_departamento
               from public.pregunta_cuestionario pc join public.bloque b on b.id = pc.bloque_id""")
PC = {(r[0], r[1]): {"bloque": r[2], "por_dep": r[3]} for r in cur.fetchall()}
cur.execute("select id, cuestionario_id, grupo_id from privado.respuesta")
RESP = {r[0]: {"cuest": r[1], "grupo": r[2]} for r in cur.fetchall()}
cur.execute("select respuesta_id, pregunta_id, asignatura_id, valor, ns_nc, departamento_id from privado.respuesta_item")
ITEMS = [dict(zip(("resp", "preg", "asig", "valor", "nsnc", "dep"), r)) for r in cur.fetchall()]
cur.execute("select respuesta_id, asignatura_id, docente_id from privado.respuesta_docente")
RD = defaultdict(set)              # (respuesta, asignatura) -> docentes
for r, a, d in cur.fetchall():
    RD[(r, a)].add(d)
cur.execute("select grupo_id, asignatura_id, docente_id from public.asignacion_docente where curso_id = %s", (CID,))
TITULARES = defaultdict(set)
for g, a, d in cur.fetchall():
    TITULARES[(g, a)].add(d)
cur.execute("select respuesta_id, tramo from privado.respuesta_tramo")
TRAMO = dict(cur.fetchall())
cur.execute("select id, nombre from public.departamento")
DEP = dict(cur.fetchall())

for it in ITEMS:
    r = RESP[it["resp"]]
    it["cuest"] = r["cuest"]
    it["grupo"] = r["grupo"]
    pc = PC.get((r["cuest"], it["preg"]))
    it["bloque"] = pc["bloque"] if pc else None
    it["por_dep"] = pc["por_dep"] if pc else None
    it["escala"] = PREG[it["preg"]]["tipo"] == "escala"
CUR_ITEMS = [i for i in ITEMS if i["cuest"] in CUEST]


def stats(items, por_pregunta, pregunta=None):
    """Cifras de un conjunto de valoraciones, como las definen la especificación y la validación."""
    validos = [i for i in items if i["valor"] is not None]
    n_val = len(validos)
    n_pers = len({i["resp"] for i in validos})
    s = {
        "n_valoraciones": n_val,
        "n_personas": n_pers,
        "ns_nc": sum(1 for i in items if i["nsnc"]),
        "media": (sum(i["valor"] for i in validos) / n_val) if n_val else None,
        "n": n_val if por_pregunta else n_pers,
    }
    if pregunta is not None:
        p = PREG[pregunta]
        s["distribucion"] = {str(v): sum(1 for i in validos if i["valor"] == v) for v in range(p["min"], p["max"] + 1)}
    return s


def items_metrica(metrica, cuests, con_asignatura):
    if metrica["tipo"] == "bloque":
        f = lambda i: i["escala"] and i["bloque"] == metrica["codigo"]
    else:
        q = PREG_COD[metrica["codigo"]]
        f = lambda i: i["preg"] == q and i["bloque"] is not None
    return [i for i in CUR_ITEMS if i["cuest"] in cuests and not i["por_dep"] and f(i)
            and (not con_asignatura or i["asig"] is not None)]


ALUMNOS = [c for c, v in CUEST.items() if v["colectivo"] == "alumnos"]
PERSONAL = [c for c, v in CUEST.items() if v["colectivo"] == "personal"]


# ---------------------------------------------------------------- clases de cada docente, desde las tablas
# Índices por cuestionario (solo tablas): quién nombró a quién en cada grupo y asignatura, y por asignatura entera.
NOMBRADOS = defaultdict(lambda: defaultdict(set))       # (cuest, grupo, asig) -> docente -> respuestas
NOMBRADOS_ASIG = defaultdict(lambda: defaultdict(set))  # (cuest, asig) -> docente -> respuestas
for (r, a), ds in RD.items():
    for d in ds:
        NOMBRADOS[(RESP[r]["cuest"], RESP[r]["grupo"], a)][d].add(r)
        NOMBRADOS_ASIG[(RESP[r]["cuest"], a)][d].add(r)
CELDAS_CACHE = {}


def celdas_de(metrica, c):
    k = (json.dumps(metrica, sort_keys=True), c)
    if k not in CELDAS_CACHE:
        its = items_metrica(metrica, {c}, True)
        por_celda = defaultdict(list)
        por_asig = defaultdict(list)
        for i in its:
            por_asig[i["asig"]].append(i)
            if i["grupo"] is not None:
                por_celda[(i["grupo"], i["asig"])].append(i)
        CELDAS_CACHE[k] = (por_celda, por_asig)
    return CELDAS_CACHE[k]


CLASES_CACHE = {}


def clases(docente, metrica, version):
    """[(clave, tipo, docentes_clase, etapa, items)] de un docente para una métrica. Un docente nombrado por el
    alumnado cuenta con 5 nombres o más; en la versión completa, con 1 (especificación §5, punto 17)."""
    MINN = 1 if version == "completa" else MIN
    k = (docente, json.dumps(metrica, sort_keys=True), version)
    if k in CLASES_CACHE:
        return CLASES_CACHE[k]
    out = []
    for c in ALUMNOS:
        etapa = CUEST[c]["etapa"]
        por_celda, por_asig = celdas_de(metrica, c)
        for (g, a), cel in por_celda.items():
            tit = TITULARES.get((g, a), set())
            if not tit:
                continue
            nombrados = NOMBRADOS.get((c, g, a), {})
            clave = (CUEST[c]["codigo"], GRUPO[g]["nombre"], ASIG[a])
            if not nombrados:
                if docente in tit:
                    out.append((clave, "propia" if len(tit) == 1 else "compartida", len(tit), etapa, cel))
                continue
            vis = set(tit) | {d for d, rs in nombrados.items() if len(rs) >= MINN}
            if docente in vis and docente in nombrados:
                sub = [i for i in cel if docente in RD.get((i["resp"], a), ())]
                if sub:
                    out.append((clave, "atribuida", len(vis), etapa, sub))
        # Optativas: asignaturas con atribución y sin titular en la etapa, por cuestionario.
        for (cc, a), por_doc in NOMBRADOS_ASIG.items():
            if cc != c or docente not in por_doc:
                continue
            if any(GRUPO[g]["etapa"] == etapa for (g, aa) in TITULARES if aa == a):
                continue
            if len(por_doc[docente]) < MINN:
                continue
            sub = [i for i in por_asig.get(a, []) if docente in RD.get((i["resp"], a), ())]
            if sub:
                out.append(((CUEST[c]["codigo"], None, ASIG[a]), "atribuida",
                            sum(1 for rs in por_doc.values() if len(rs) >= MINN), etapa, sub))
    CLASES_CACHE[k] = out
    return out


def clave_plat(c):
    k = c["clave"]
    return (k["cuestionario"], k.get("grupo"), k["asignatura"])


# ---------------------------------------------------------------- informes de la plataforma
def como_direccion(version):
    cur.version = version


cur.execute("""select d.id from public.persona_responsable d
               where exists (select 1 from public.asignacion_docente a where a.docente_id = d.id and a.curso_id = %s)
                  or exists (select 1 from privado.respuesta_docente r where r.docente_id = d.id) order by d.id""", (CID,))
DOCENTES = [r[0] for r in cur.fetchall()]

informes = {}
for version in ("completa", "docente"):
    como_direccion(version)
    for d in DOCENTES:
        cur.execute("select privado.informe_profesor(%s::smallint, %s, null::text)", (CID, d))
        informes[(version, d)] = cur.fetchone()[0]
(SALIDA / "informes_profesor.json").write_text(json.dumps({f"{v}:{d}": x for (v, d), x in informes.items()}))


def etapas_de(metrica):
    q = None if metrica["tipo"] == "bloque" else PREG_COD[metrica["codigo"]]
    es = set()
    for (c, p), v in PC.items():
        if CUEST.get(c, {}).get("colectivo") != "alumnos":
            continue
        if (q is None and v["bloque"] == metrica["codigo"] and PREG[p]["tipo"] == "escala") or p == q:
            es.add(CUEST[c]["etapa"])
    return es


REF_CACHE = {}


def referencia(metrica, cuests):
    k = (json.dumps(metrica, sort_keys=True), tuple(sorted(cuests)))
    if k not in REF_CACHE:
        REF_CACHE[k] = stats(items_metrica(metrica, set(cuests), False), metrica["tipo"] == "pregunta")
    return REF_CACHE[k]


def comprobar_resultado(ap, donde, version, metrica, res, mias, visibles_bloque=None):
    """Una métrica del informe de un docente: clases, media del docente y comparación."""
    por_pregunta = metrica["tipo"] == "pregunta"
    q = PREG_COD[metrica["codigo"]] if por_pregunta else None
    plat = {clave_plat(c): c for c in res["celdas"]}
    mias_k = {m[0]: m for m in mias}
    cmp(ap, donde, "clases (conjunto)", sorted(map(str, mias_k)), sorted(map(str, plat)))
    vis_suma = 0.0; vis_nval = 0; vis_nper = 0; vis_n = 0; menos5 = 0; excl = 0; comp = 0
    for k, (clave, tipo, ndoc, etapa, its) in mias_k.items():
        c = plat.get(k)
        if c is None:
            continue
        s = stats(its, por_pregunta, q)
        w = f"{donde} · {k}"
        cmp(ap, w, "tipo", tipo, c["tipo"]); cmp(ap, w, "etapa", etapa, c["etapa"]); cmp(ap, w, "docentes", ndoc, c["docentes_clase"])
        if c["suprimido"]:
            if version == "completa":
                regla(ap, w, c["motivo"] == "sin_datos" and s["n"] == 0, f"oculta en la versión completa ({c['motivo']}, n {s['n']})")
            elif c["motivo"] == "menos_de_5":
                regla(ap, w, s["n"] < MIN, f"«menos de 5» con n {s['n']}")
            else:
                regla(ap, w, s["n"] >= MIN, f"«{c['motivo']}» con n {s['n']} (debería ser «menos de 5»)")
        else:
            for f in ("n", "n_personas", "n_valoraciones", "ns_nc", "media"):
                cmp(ap, w, f, s[f], c.get(f))
            if por_pregunta:
                for v, x in s["distribucion"].items():
                    cmp(ap, w, f"distribución {v}", x, c["distribucion"].get(v))
            if version == "docente":
                regla(ap, w, s["n"] >= MIN and not c.get("menos_de_5"), f"visible con n {s['n']} en la versión docente")
            else:
                cmp(ap, w, "marca menos de 5", s["n"] < MIN, bool(c.get("menos_de_5")))
        if tipo == "compartida":
            comp += 1
        elif not c["suprimido"]:
            vis_n += 1; s2 = s
            vis_nval += s2["n_valoraciones"]; vis_nper += s2["n_personas"]; vis_suma += (s2["media"] or 0) * s2["n_valoraciones"]
            menos5 += s2["n"] < MIN
        else:
            excl += 1
    g = res["global"]
    if vis_n == 0:
        cmp(ap, donde, "media global oculta", True, g["suprimido"])
    else:
        cmp(ap, donde, "media global", vis_suma / vis_nval if vis_nval else None, g.get("media"))
        cmp(ap, donde, "global: clases", vis_n, g.get("combinaciones"))
        cmp(ap, donde, "global: valoraciones", vis_nval, g.get("n_valoraciones"))
        if not por_pregunta or version == "completa":
            cmp(ap, donde, "global: personas por asignatura", vis_nper, g.get("n_personas_por_asignatura"))
        cmp(ap, donde, "global: clases con menos de 5", menos5 or None, g.get("menos_de_5"))
    cmp(ap, donde, "clases excluidas", excl, res.get("combinaciones_excluidas"))
    if "compartidas" in res and not por_pregunta:
        cmp(ap, donde, "compartidas", comp, res["compartidas"])
    # Comparación: etapas en que tiene clases con la métrica, y el Colegio.
    etapas = {m[3] for m in mias}
    cmp(ap, donde, "etapas de la comparación", sorted(etapas), sorted(k for k in res["comparacion"] if k != "colegio"))
    for e in etapas:
        ref = referencia(metrica, [c for c in ALUMNOS if CUEST[c]["etapa"] == e])
        x = res["comparacion"].get(e)
        if x:
            cmp(ap, donde, f"media de {e} (todo el profesorado)", ref["media"], x.get("media"))
            if version == "completa":
                cmp(ap, donde, f"n de {e}", ref["n"], x.get("n"))
            else:
                regla(ap, donde, set(x) <= {"clave", "suprimido", "motivo", "media"}, f"la comparación de {e} lleva más que la media")
    colegio_esperado = version == "completa" or len(etapas_de(metrica)) != 2
    cmp(ap, donde, "lleva media del Colegio", colegio_esperado, "colegio" in res["comparacion"])
    if "colegio" in res["comparacion"]:
        ref = referencia(metrica, ALUMNOS)
        cmp(ap, donde, "media del Colegio", ref["media"], res["comparacion"]["colegio"].get("media"))
        if version == "completa":
            cmp(ap, donde, "n del Colegio", ref["n"], res["comparacion"]["colegio"].get("n"))
    return vis_suma, vis_nval


BLOQUE = {"tipo": "bloque", "codigo": "profesorado"}
clases_bloque = {}
for d in DOCENTES:
    for version in ("completa", "docente"):
        clases_bloque[(d, version)] = clases(d, BLOQUE, version)
        inf = informes[(version, d)]
        ap = f"Profesorado · versión {version}"
        donde = f"docente {d}"
        cmp(ap, donde, "versión", version, inf["version"])
        comprobar_resultado(ap, donde, version, BLOQUE, inf, clases_bloque[(d, version)])
        if version == "completa":
            # La media global de la versión docente, que la completa enseña al lado.
            doc = informes[("docente", d)]
            cmp(ap, donde, "media global en la versión docente", doc["global"].get("media"), (inf.get("global_docente") or {}).get("media"))
        bloque_vis = {clave_plat(c): not c["suprimido"] for c in inf["celdas"]}
        for p in inf["preguntas"]:
            m = {"tipo": "pregunta", "codigo": p["codigo"]}
            mias = clases(d, m, version)
            comprobar_resultado(ap, f"{donde} · {p['codigo'][16:60]}", version, m, p["resultado"], mias)
        if version == "docente":
            # Paso por clase: en una clase visible no queda oculta una sola pregunta; en una oculta, ninguna se ve.
            por_clase = defaultdict(list)
            for p in inf["preguntas"]:
                for c in p["resultado"]["celdas"]:
                    por_clase[clave_plat(c)].append(c["suprimido"])
            for k, ocultas in por_clase.items():
                if bloque_vis.get(k):
                    regla(ap, f"{donde} · {k}", sum(ocultas) != 1, "una sola pregunta oculta en una clase visible")
                else:
                    regla(ap, f"{donde} · {k}", all(ocultas), "pregunta visible en una clase oculta")

# ---------------------------------------------------------------- jefaturas de departamento
cur.execute("""select persona_id, array_agg(ambito order by ambito) from public.cargo
               where curso_id = %s and tipo = 'jefe_departamento' group by persona_id order by persona_id""", (CID,))
JEFES = cur.fetchall()
cur.execute("""select o.nombre, de.nombre from public.departamento_equivalencia eq
               join public.departamento o on o.id = eq.departamento_id join public.departamento de on de.id = eq.departamento_encuesta_id""")
EQUIV = defaultdict(set)
for o, de in cur.fetchall():
    EQUIV[o].add(de)
deps_con_items = {DEP[i["dep"]] for i in CUR_ITEMS if i["dep"] is not None}
cur.execute("select id, departamento_id from public.persona_responsable")
DEP_DE = dict(cur.fetchall())

jef = {}
for version in ("completa", "jefatura"):
    como_direccion(version)
    for pid, deps in JEFES:
        cur.execute("select privado.informe_jefatura_departamento(%s, %s)", (CURSO, pid))
        jef[(version, pid)] = cur.fetchone()[0]


def items_personal(bloque, filtro, q=None):
    return [i for i in CUR_ITEMS if i["cuest"] in PERSONAL and i["bloque"] == bloque and i["escala"]
            and (q is None or i["preg"] == q) and filtro(i)]


def comprobar_seccion(ap, donde, version, bloque, filtro, sec):
    tot = stats(items_personal(bloque, filtro), False)
    t = sec["total"]
    if t["suprimido"]:
        if version == "completa":
            regla(ap, donde, tot["n"] == 0, f"total oculto en la versión completa con n {tot['n']}")
        elif t.get("motivo") == "menos_de_5":
            regla(ap, donde, tot["n"] < MIN, f"«menos de 5» con n {tot['n']}")
        else:
            regla(ap, donde, tot["n"] >= MIN, f"«{t.get('motivo')}» con n {tot['n']}")
        return
    for f in ("n", "n_personas", "n_valoraciones", "ns_nc", "media"):
        cmp(ap, donde, f"total {f}", tot[f], t.get(f))
    if version != "completa":
        regla(ap, donde, tot["n"] >= MIN, f"total visible con n {tot['n']}")
    qs = {PREG_COD[p["codigo"]] for p in sec["preguntas"]}
    esperadas = {i["preg"] for i in items_personal(bloque, filtro)}
    cmp(ap, donde, "preguntas (conjunto)", sorted(PREG[q]["codigo"] for q in esperadas), sorted(PREG[q]["codigo"] for q in qs))
    for p in sec["preguntas"]:
        q = PREG_COD[p["codigo"]]
        s = stats(items_personal(bloque, filtro, q), True, q)
        x = p["resultado"]["total"]
        w = f"{donde} · {p['codigo'][4:60]}"
        if x["suprimido"]:
            if version == "completa":
                regla(ap, w, s["n"] == 0, f"oculta en la versión completa con n {s['n']}")
            elif x.get("motivo") == "menos_de_5":
                regla(ap, w, s["n"] < MIN, f"«menos de 5» con n {s['n']}")
            else:
                regla(ap, w, s["n"] >= MIN, f"«{x.get('motivo')}» con n {s['n']}")
            continue
        for f in ("n", "n_valoraciones", "ns_nc", "media"):
            cmp(ap, w, f, s[f], x.get(f))
        for v, k in s["distribucion"].items():
            cmp(ap, w, f"distribución {v}", k, x["distribucion"].get(v))
        if version != "completa":
            regla(ap, w, s["n"] >= MIN, f"visible con n {s['n']}")
        else:
            cmp(ap, w, "marca menos de 5", s["n"] < MIN, bool(x.get("menos_de_5")))


for (version, pid), inf in jef.items():
    deps = dict(JEFES)[pid]
    ap = f"Jefatura de departamento · versión {version}"
    donde = f"jefatura {pid}"
    unidades = sorted(set().union(*[EQUIV[o] for o in deps]) | {o for o in deps if o in deps_con_items})
    for sec in inf["reuniones"]:
        u = set(sec["unidades"])
        regla(ap, donde, u <= set(unidades), f"unidades {u} fuera de {unidades}")
        comprobar_seccion(ap, f"{donde} · {sorted(u)}", version, "reuniones_departamento",
                          lambda i, u=u: i["dep"] is not None and DEP[i["dep"]] in u and i["por_dep"], sec)
    if len(unidades) <= 1 or not inf["reuniones"] or not inf["reuniones"][0].get("conjunto"):
        cmp(ap, donde, "unidades de las secciones", unidades if inf["reuniones"] else [],
            sorted(set().union(*[set(s["unidades"]) for s in inf["reuniones"]])) if inf["reuniones"] else [])
    # Profesorado de sus departamentos según el alumnado: sus clases propias visibles, con la visibilidad del
    # informe de cada docente en la misma versión.
    vd = "completa" if version == "completa" else "docente"
    cur.execute("""select distinct pr.id from public.persona_responsable pr join public.departamento d on d.id = pr.departamento_id
                   where d.curso_id = %s and d.nombre = any(%s)""", (CID, list(deps)))
    docs = [r[0] for r in cur.fetchall() if (r[0], vd) in clases_bloque]
    suma = 0.0; nval = 0; vis = 0; m5 = 0; exc = 0
    for d in docs:
        visib = {clave_plat(c): not c["suprimido"] for c in informes[(vd, d)]["celdas"]}
        for clave, tipo, ndoc, etapa, its in clases_bloque[(d, vd)]:
            if tipo == "compartida":
                continue
            if visib.get(clave):
                s = stats(its, False)
                vis += 1; nval += s["n_valoraciones"]; suma += s["media"] * s["n_valoraciones"]; m5 += s["n"] < MIN
            else:
                exc += 1
    m = inf["alumnos"]["media"]
    cmp(ap, donde, "docentes del departamento", len(docs), m["profesores"])
    if vis:
        cmp(ap, donde, "media del profesorado según el alumnado", suma / nval, m["global"].get("media"))
        cmp(ap, donde, "clases", vis, m["global"].get("combinaciones"))
        cmp(ap, donde, "valoraciones", nval, m["global"].get("n_valoraciones"))
        cmp(ap, donde, "clases con menos de 5", m5 or None, m["global"].get("menos_de_5"))
    else:
        cmp(ap, donde, "media oculta", True, m["global"]["suprimido"])
    cmp(ap, donde, "clases excluidas", exc, m["combinaciones_excluidas"])

# ---------------------------------------------------------------- Equipo de Individuación
for version in ("completa", "jefatura"):
    como_direccion(version)
    ap = f"Equipo de Individuación · versión {version}"
    cur.execute("select privado.grupos_equipo(%s)", (CURSO,))
    grupos = cur.fetchone()[0]
    n_tramo = {t: stats(items_personal("equipo_individualizacion", lambda i, t=t: TRAMO.get(i["resp"]) == t), False)["n"]
               for t in ("infantil", "y1_y5", "y6_y9", "y10_y12")}
    for g in grupos:
        ts = g["tramos"]
        if len(ts) == 1:
            regla(ap, f"tramo {ts}", version == "completa" or n_tramo[ts[0]] >= MIN, f"tramo solo con n {n_tramo[ts[0]]}")
    if version == "jefatura":
        ocultos = [t for t in n_tramo if n_tramo[t] and n_tramo[t] < MIN]
        juntos = [g["tramos"] for g in grupos if len(g["tramos"]) > 1]
        regla(ap, "tramos", all(any(t in j for j in juntos) for t in ocultos), f"tramos de menos de 5 {ocultos} no van juntos: {grupos}")
    for g in grupos:
        cur.execute("select privado.informe_jefatura_equipo(%s, %s, %s)", (CURSO, g["tramos"], version == "jefatura"))
        inf = cur.fetchone()[0]
        ts = set(inf["tramos"])
        comprobar_seccion(ap, f"tramos {sorted(ts)}", version, "equipo_individualizacion",
                          lambda i, ts=ts: TRAMO.get(i["resp"]) in ts, inf)

# ---------------------------------------------------------------- tutoría y servicios (§7.12 y §7.13)
from informes_2526 import SERVICIOS, TUTORIA_COLEGIO, TUTORIA_GRUPO  # noqa: E402

cur.execute("select respuesta_id, etapa from privado.respuesta_etapa")
ETAPAS_FAM = defaultdict(set)
for r, e in cur.fetchall():
    ETAPAS_FAM[r].add(e)
FAMILIAS = [c for c, v in CUEST.items() if v["colectivo"] == "familias"]
DE_COLECTIVO = {"alumnos": set(ALUMNOS), "familias": set(FAMILIAS), "personal": set(PERSONAL)}
ORDEN_ETAPAS = ["infantil", "primaria", "pai", "bachillerato"]
ETIQUETA_ETAPA = {"Infantil": "infantil", "Primaria": "primaria", "PAI": "pai", "Bachillerato": "bachillerato"}


def colectivo_de(codigo):
    cs = {CUEST[c]["colectivo"] for (c, p) in PC if p == PREG_COD.get(codigo) and c in CUEST}
    return cs.pop() if len(cs) == 1 else None


def items_q(q, cuests, filtro=lambda i: True):
    return [i for i in CUR_ITEMS if i["cuest"] in cuests and i["preg"] == q and i["bloque"] is not None
            and not i["por_dep"] and filtro(i)]


def comprobar_fila(ap, donde, version, s, x, por_pregunta=True):
    """Una celda: sus cifras si se ve; si está oculta, que el motivo encaje con su número de respuestas."""
    if x is None:
        diferencias.append(f"[{ap}] {donde} · falta en la plataforma")
        return
    if x["suprimido"]:
        if version == "completa":
            regla(ap, donde, s["n"] == 0, f"oculta en la versión completa con n {s['n']}")
        elif x.get("motivo") == "menos_de_5":
            regla(ap, donde, s["n"] < MIN, f"«menos de 5» con n {s['n']}")
        elif x.get("motivo") == "sin_datos":
            regla(ap, donde, s["n"] == 0, f"«sin datos» con n {s['n']}")
        else:
            regla(ap, donde, s["n"] >= MIN, f"«{x.get('motivo')}» con n {s['n']}")
        return
    for f in ("n", "n_personas", "n_valoraciones", "ns_nc", "media"):
        cmp(ap, donde, f, s[f], x.get(f))
    if por_pregunta:
        for v, k in s["distribucion"].items():
            cmp(ap, donde, f"distribución {v}", k, x["distribucion"].get(v))
    if version != "completa":
        regla(ap, donde, s["n"] >= MIN, f"visible con n {s['n']}")
    else:
        cmp(ap, donde, "marca menos de 5", s["n"] < MIN, bool(x.get("menos_de_5")))


def celda_esperada(s, x):
    """Lo que tiene que enseñar la tabla del frontend en una celda."""
    if x is None:
        return {"nota": "no_se_pregunta"}
    if x["suprimido"]:
        return {"nota": {"menos_de_5": "menos_de_5", "sin_datos": "sin_datos"}.get(x.get("motivo"), "complementaria")}
    if s["n_valoraciones"] == 0:
        return {"nota": "sin_datos"}     # visible en la versión completa, pero todas las respuestas son NS/NC
    return {"media": s["media"], "n": s["n_valoraciones"]}


resumen_esperado = {}     # clave del frontend -> celda esperada

# Catálogo: lo cargado frente a etl/informes_2526.py
cur.execute("""select p.codigo_diccionario, tp.ambito from public.tutoria_pregunta tp join public.pregunta p on p.id = tp.pregunta_id
               where tp.curso_id = %s order by tp.ambito, tp.orden""", (CID,))
cat = cur.fetchall()
cmp("Tutoría · catálogo", "etl/informes_2526.py", "preguntas del grupo", TUTORIA_GRUPO, [c for c, a in cat if a == "grupo"])
cmp("Tutoría · catálogo", "etl/informes_2526.py", "referencias del Colegio", TUTORIA_COLEGIO, [c for c, a in cat if a == "colegio"])

# Tutores: lo cargado frente a la hoja «Tutores» de Alexia, con un emparejamiento propio («Y6-B.Comp» es «Y6 B»).
cur.execute("select grupo_id, persona_id from public.tutoria where curso_id = %s", (CID,))
TUTOR = dict(cur.fetchall())
cur.execute("select id, lower(correo) from public.persona_responsable")
CORREO = dict(cur.fetchall())
ALEXIA = RAIZ / "datos_locales" / "fuentes" / "Grupos_asignaturas_docentes_2025-26.xlsx"
GRUPO_NOMBRE = {v["nombre"]: k for k, v in GRUPO.items()}
if ALEXIA.exists():
    import re
    import openpyxl
    hoja = list(openpyxl.load_workbook(ALEXIA, read_only=True, data_only=True)["Tutores"].iter_rows(values_only=True))
    cab = [str(c or "").strip() for c in hoja[0]]
    esperado_tutor = {}
    for fila in hoja[1:]:
        f = dict(zip(cab, fila))
        nombre = re.sub(r"\.Comp$", "", str(f.get("Grupo") or "").strip()).replace("-", " ")
        if nombre in GRUPO_NOMBRE and f.get("Correo tutor/a"):
            esperado_tutor[GRUPO_NOMBRE[nombre]] = str(f["Correo tutor/a"]).strip().lower()
    cmp("Tutoría · tutores (Alexia)", "hoja Tutores", "grupos con tutor/a", sorted(GRUPO[g]["nombre"] for g in esperado_tutor),
        sorted(GRUPO[g]["nombre"] for g in TUTOR))
    for g, correo in esperado_tutor.items():
        cmp("Tutoría · tutores (Alexia)", GRUPO[g]["nombre"], "correo del tutor/a", correo, CORREO.get(TUTOR.get(g)))

CUEST_GRUPO = {}
_cuenta = defaultdict(lambda: defaultdict(int))
for r in RESP.values():
    if r["grupo"] is not None and r["cuest"] in ALUMNOS:
        _cuenta[r["grupo"]][r["cuest"]] += 1
for g, cs in _cuenta.items():
    CUEST_GRUPO[g] = max(cs, key=lambda c: (cs[c], -ord(CUEST[c]["codigo"][0])))
GRUPOS_TUT = sorted(set(CUEST_GRUPO) | set(TUTOR), key=lambda g: GRUPO[g]["nombre"])

informes_tut = {}
for version in ("completa", "tutor"):
    como_direccion(version)
    ap = f"Tutoría · versión {version}"
    ocultos = defaultdict(set)
    for g in GRUPOS_TUT:
        cur.execute("select privado.informe_tutoria(%s, %s)", (CURSO, g))
        inf = cur.fetchone()[0]
        informes_tut[f"{version}:{g}"] = inf
        donde = GRUPO[g]["nombre"]
        c = CUEST_GRUPO.get(g)
        etapa = GRUPO[g]["etapa"]
        cmp(ap, donde, "tutor/a", TUTOR.get(g), (inf["tutor"] or {}).get("id"))
        cmp(ap, donde, "cuestionario", CUEST[c]["codigo"] if c else None, inf["grupo"]["cuestionario"])
        cmp(ap, donde, "preguntas", [x for x in TUTORIA_GRUPO if c and (c, PREG_COD[x]) in PC], [p["codigo"] for p in inf["preguntas"]])
        for p in inf["preguntas"]:
            q = PREG_COD[p["codigo"]]
            w = f"{donde} · {p['codigo'][26:70]}"
            s = stats(items_q(q, {c}, lambda i, g=g: i["grupo"] == g), True, q)
            comprobar_fila(ap, f"{w} · grupo", version, s, p["grupo"])
            if p["grupo"]["suprimido"]:
                ocultos[(c, q)].add(donde)
            se = stats(items_q(q, {x for x in ALUMNOS if CUEST[x]["etapa"] == etapa}), True, q)
            comprobar_fila(ap, f"{w} · toda la etapa", version, se, p["etapa"])
            resumen_esperado[f"{version}:{g}|grupo|{p['codigo']}|0"] = celda_esperada(s, p["grupo"])
            resumen_esperado[f"{version}:{g}|grupo|{p['codigo']}|1"] = celda_esperada(se, p["etapa"])
        cmp(ap, donde, "referencias del Colegio", TUTORIA_COLEGIO, [x["codigo"] for x in inf["colegio"]])
        for x in inf["colegio"]:
            q = PREG_COD[x["codigo"]]
            col = colectivo_de(x["codigo"])
            cmp(ap, donde, f"colectivo de {x['codigo'][:40]}", col, x["colectivo"])
            s = stats(items_q(q, DE_COLECTIVO[col]), True, q)
            comprobar_fila(ap, f"{donde} · Colegio · {col}", version, s, x["total"])
            resumen_esperado[f"{version}:{g}|colegio|{x['codigo']}|0"] = celda_esperada(s, x["total"])
    if version == "tutor":
        # Complementaria entre los grupos de cada cuestionario: nunca un solo grupo oculto. Las respuestas sin grupo son
        # una parte más: si tienen 5 o más, no se sabe si están ocultas y no se comprueba.
        for c in ALUMNOS:
            for codigo in TUTORIA_GRUPO:
                q = PREG_COD[codigo]
                if (c, q) not in PC:
                    continue
                sin = items_q(q, {c}, lambda i: i["grupo"] is None)
                n_sin = stats(sin, True)["n"]
                if sin and n_sin >= MIN:
                    continue
                k = len(ocultos[(c, q)]) + (1 if sin else 0)
                regla(ap, f"{CUEST[c]['codigo']} · {codigo[26:70]}", k != 1, f"un solo grupo oculto: {sorted(ocultos[(c, q)])}")
(SALIDA / "informes_tutoria.json").write_text(json.dumps(informes_tut))

cur.execute("select id, codigo, nombre from public.servicio where curso_id = %s order by orden", (CID,))
SERV = cur.fetchall()
DEF = {c: (n, p, e) for c, n, p, e in SERVICIOS}
cmp("Servicios · catálogo", "etl/informes_2526.py", "servicios", [(c, n) for c, n, _, _ in SERVICIOS], [(c, n) for _, c, n in SERV])

informes_srv = {}
for version in ("completa", "responsable"):
    como_direccion(version)
    ap = f"Servicios · versión {version}"
    for sid, codigo_s, nombre in SERV:
        cur.execute("select privado.informe_servicio(%s, %s)", (CURSO, sid))
        inf = cur.fetchone()[0]
        informes_srv[f"{version}:{sid}"] = inf
        _, principales, propias = DEF.get(codigo_s, (None, [], []))
        cols = [c for c in ("alumnos", "familias", "personal") if any(colectivo_de(x) == c for x in principales + propias)]
        cmp(ap, nombre, "colectivos", cols, [x["colectivo"] for x in inf["colectivos"]])
        for x in inf["colectivos"]:
            col = x["colectivo"]
            cuests = DE_COLECTIVO[col]
            esperadas = [(c, True) for c in principales if colectivo_de(c) == col] + [(c, False) for c in propias if colectivo_de(c) == col]
            cmp(ap, f"{nombre} · {col}", "preguntas", esperadas, [(p["codigo"], p["principal"]) for p in x["preguntas"]])
            etapas_tabla = set()
            for p in x["preguntas"]:
                q = PREG_COD[p["codigo"]]
                w = f"{nombre} · {col} · {p['codigo'][:60]}"
                todos = items_q(q, cuests)
                st = stats(todos, True, q)
                comprobar_fila(ap, f"{w} · total", version, st, p["total"])
                resumen_esperado[f"{version}:{sid}|{col}|{p['codigo']}|total"] = celda_esperada(st, p["total"])
                partes = defaultdict(list)
                for i in todos:
                    if col == "alumnos":
                        partes[GRUPO[i["grupo"]]["etapa"] if i["grupo"] is not None else CUEST[i["cuest"]]["etapa"]].append(i)
                    elif col == "familias":
                        for e in ETAPAS_FAM.get(i["resp"], ()):
                            partes[e].append(i)
                cmp(ap, w, "etapas", sorted(partes), sorted(e["clave"]["etapa"] for e in p["etapas"]))
                etapas_tabla |= set(partes)
                for e in p["etapas"]:
                    et = e["clave"]["etapa"]
                    se = stats(partes.get(et, []), True, q)
                    comprobar_fila(ap, f"{w} · {et}", version, se, e)
                    resumen_esperado[f"{version}:{sid}|{col}|{p['codigo']}|{et}"] = celda_esperada(se, e)
                if version != "completa" and col == "alumnos" and not p["total"]["suprimido"]:
                    regla(ap, w, sum(1 for e in p["etapas"] if e["suprimido"]) != 1, "una sola etapa oculta")
            resumen_esperado[f"{version}:{sid}|{col}|etapas"] = [e for e in ORDEN_ETAPAS if e in etapas_tabla]
            sref = stats(items_metrica({"tipo": "bloque", "codigo": "servicios"}, cuests, False), False)
            if x["servicios"] is not None:
                comprobar_fila(ap, f"{nombre} · {col} · media de todos los servicios", version, sref, x["servicios"], por_pregunta=False)
                resumen_esperado[f"{version}:{sid}|{col}|referencia"] = celda_esperada(sref, x["servicios"])
            else:
                regla(ap, f"{nombre} · {col}", not any(i["bloque"] == "servicios" for i in CUR_ITEMS if i["cuest"] in cuests),
                      "falta la media de todos los servicios")
(SALIDA / "informes_servicio.json").write_text(json.dumps(informes_srv))

cur.conn.close()

# ---------------------------------------------------------------- tabla «Detalle por pregunta» del frontend
# (src/data/tablaProfesor.ts ejecutado con vite-node sobre los mismos informes: tabla_frontend.json)
subprocess.run(["npx", "vite-node", str(RAIZ / "etl" / "verificar_tabla_frontend.ts"), str(SALIDA)],
               cwd=RAIZ, check=True, stdout=subprocess.DEVNULL)
tf = SALIDA / "tabla_frontend.json"
if tf.exists():
    tabla = json.loads(tf.read_text())
    for clave, v in tabla.items():
        vk, codigo, tipo, etapa = clave.split("|")
        version, d = vk.split(":"); d = int(d)
        ap = f"Tabla del informe (frontend) · versión {version}"
        w = f"docente {d} · {codigo[16:60]} · {tipo} {etapa}"
        m = {"tipo": "pregunta", "codigo": codigo}
        res = next(p["resultado"] for p in informes[(version, d)]["preguntas"] if p["codigo"] == codigo)
        visible = {clave_plat(c): not c["suprimido"] for c in res["celdas"]}
        mias = clases(d, m, version)
        if tipo in ("docente", "docente_etapa"):
            sel = [x for x in mias if tipo == "docente" or x[3] == etapa]
            propias = [x for x in sel if x[1] != "compartida"]
            vis = [x for x in propias if visible.get(x[0])]
            nval = sum(stats(x[4], True)["n_valoraciones"] for x in vis)
            if not sel:
                esperado = {"nota": "no_se_pregunta"}
            elif not propias:
                esperado = {"nota": "sin_propias"}
            elif nval == 0:
                esperado = {"nota": "sin_visibles"}
            else:
                esperado = {"media": sum(stats(x[4], True)["media"] * stats(x[4], True)["n_valoraciones"] for x in vis) / nval}
        elif tipo == "etapa":
            if not any(x[3] == etapa for x in mias):
                esperado = {"nota": "no_se_pregunta"}
            else:
                esperado = {"media": referencia(m, [c for c in ALUMNOS if CUEST[c]["etapa"] == etapa])["media"]}
        else:
            if version == "docente" and len(etapas_de(m)) == 2:
                esperado = {"nota": "no_se_muestra"}
            else:
                esperado = {"media": referencia(m, ALUMNOS)["media"]}
        if "media" in esperado:
            cmp(ap, w, "media", esperado["media"], v.get("media"))
        else:
            cmp(ap, w, "nota", esperado["nota"], v.get("nota"))

# Tablas de tutoría y de servicios del frontend (src/data/tablasResumen.ts): cada celda como la que se espera.
rf = SALIDA / "resumen_frontend.json"
if rf.exists():
    front = json.loads(rf.read_text())

    def cmp_celda(ap, w, esperado, v):
        if v is None:
            diferencias.append(f"[{ap}] {w} · falta en la tabla")
        elif "media" in esperado:
            cmp(ap, w, "media", esperado["media"], v.get("media"))
            cmp(ap, w, "respuestas", esperado["n"], v.get("n"))
        else:
            cmp(ap, w, "nota", esperado["nota"], v.get("nota"))

    for k, esperado in resumen_esperado.items():
        clave, tabla, *resto = k.split("|")
        version = clave.split(":")[0]
        if tabla in ("grupo", "colegio"):
            cmp_celda(f"Tablas de tutoría (frontend) · versión {version}", k, esperado, front.get(k))
            continue
        ap = f"Tablas de servicios (frontend) · versión {version}"
        if resto == ["etapas"]:
            cols = front.get(f"{clave}|{tabla}|columnas") or []
            cmp(ap, k, "columnas de etapa", esperado, [ETIQUETA_ETAPA.get(c, c) for c in cols[1:]])
        elif resto == ["referencia"]:
            cmp_celda(ap, k, esperado, front.get(k))
        else:
            codigo, col = resto
            cols = front.get(f"{clave}|{tabla}|columnas") or []
            if col == "total":
                i = 0
            else:
                etiquetas = [ETIQUETA_ETAPA.get(c) for c in cols]
                i = etiquetas.index(col) if col in etiquetas else -1
            cmp_celda(ap, k, esperado, front.get(f"{clave}|{tabla}|{codigo}|{i}") if i >= 0 else None)
    # Las celdas de etapas en las que no se pregunta, «no se pregunta».
    for k, v in front.items():
        partes = k.split("|")
        if len(partes) == 4 and partes[1] in ("alumnos", "familias") and partes[3] != "0":
            clave, col, codigo, i = partes
            cols = front.get(f"{clave}|{col}|columnas") or []
            et = ETIQUETA_ETAPA.get(cols[int(i)]) if int(i) < len(cols) else None
            if f"{clave}|{col}|{codigo}|{et}" not in resumen_esperado:
                cmp(f"Tablas de servicios (frontend) · versión {clave.split(':')[0]}", k, "nota", "no_se_pregunta", v.get("nota"))

# ---------------------------------------------------------------- resumen
lineas = [f"# Verificación independiente de los informes {CURSO} ({'nube' if ARGS.remoto else 'local'})", "",
          f"Docentes: {len(DOCENTES)} · jefaturas de departamento: {len(JEFES)} · grupos (tutoría): {len(GRUPOS_TUT)} · servicios: {len(SERV)}", "", "## Cifras comparadas", ""]
lineas += [f"- {k}: {comparadas[k]:,}".replace(",", ".") for k in sorted(comparadas)]
lineas += [f"- **Total: {sum(comparadas.values()):,}**".replace(",", "."), "", "## Comprobaciones del criterio de anonimato", ""]
lineas += [f"- {k}: {anonimato[k]:,}".replace(",", ".") for k in sorted(anonimato)]
lineas += [f"- **Total: {sum(anonimato.values()):,}**".replace(",", "."), "", f"## Diferencias: {len(diferencias)}", ""]
lineas += [f"- {x}" for x in diferencias]
destino = RAIZ / "datos_locales" / "informes" / ("verificacion_informes_2526_nube.md" if ARGS.remoto else "verificacion_informes_2526.md")
destino.parent.mkdir(parents=True, exist_ok=True)
destino.write_text("\n".join(lineas) + "\n")
TEMPORAL.cleanup()
print("\n".join(lineas[:-len(diferencias)] if diferencias else lineas))
if diferencias:
    print(f"Las {len(diferencias)} diferencias, en {destino.relative_to(RAIZ)}")
print(f"Guardado en {destino.relative_to(RAIZ)}")
USO.resultado = f"{len(diferencias)} diferencias" if diferencias else "sin diferencias"
USO.cifras = sum(comparadas.values())
sys.exit(1 if diferencias else 0)
