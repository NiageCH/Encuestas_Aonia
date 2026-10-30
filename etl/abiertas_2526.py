"""Respuestas abiertas de 2025/26 (decisión confirmada por Mark, especificación §7.9).

Se cargan tal cual, sin ocultar nada, y solo las ven Dirección y administración. Cada respuesta abierta se guarda suelta:
con su pregunta y lo necesario para filtrar (grupo en alumnado, etapas en familias, docente o no y antigüedad en
personal), pero sin ningún enlace con las respuestas cerradas de la misma persona.

Qué columnas son preguntas abiertas:
- las de «Respuesta abierta» de Encuesta Fácil, salvo las que piden el nombre de un docente o de la optativa (sirven
  solo para atribuir valoraciones, §7.2, y no se cargan);
- en personal, las tres de «respuesta libre» del bloque del Plan de Igualdad (se cargan desde el 30/10/2026, decisión de
  Mark: solo para Dirección y administración, como el resto).

Este módulo solo extrae: no imprime ningún texto de respuesta. La carga está en cargar_abiertas_2526.py.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional, Set

from cuestionarios_2526 import DEFINICIONES, REGLAS, Conversor, Diccionario, Respuesta
from encuesta_facil import Columna, leer

# Código común de cada pregunta abierta (la misma pregunta en varios cuestionarios), por su texto. Se guarda el texto de
# cada cuestionario tal como está; la pantalla las agrupa por el código.
CODIGOS = [
    (r"echas? en falta", "echa_en_falta", "¿Qué echa en falta en el Colegio?"),
    (r"comentario", "comentario", "Comentarios"),
    (r"necesidades identifica en el Colegio que el Plan", "igualdad_necesidades", None),
    (r"medidas podría adoptar el Colegio para promover la igualdad", "igualdad_medidas", None),
    (r"^Otras sugerencias", "igualdad_sugerencias", None),
]

# Columnas que piden un nombre (docente u optativa): no son opiniones y no se cargan.
NOMBRES = re.compile(r"nombre de (tu|la) (profesora?|OPTATIVA)", re.IGNORECASE)

# Familias: la exportación no trae el texto de sus dos preguntas abiertas (la cabecera es la del bloque). Se reconocen por
# su orden y llevan el texto oficial del cuestionario, confirmado por Mark el 30/10/2026.
FAMILIAS = [
    ("echa_en_falta", "¿Qué es lo que echa en falta en el Colegio?"),
    ("comentario", "Si desea añadir algún comentario, hágalo aquí por favor"),
]


@dataclass
class Abierta:
    texto: str
    grupo: Optional[str] = None
    etapas: Set[str] = field(default_factory=set)
    docente: Optional[bool] = None
    antiguedad: Optional[str] = None


@dataclass
class PreguntaAbierta:
    cuestionario: str
    colectivo: str
    orden: int
    codigo: str
    texto: str
    nota: Optional[str] = None
    respuestas: List[Abierta] = field(default_factory=list)


@dataclass
class Descartada:
    cuestionario: str
    texto: str
    n: int


def _codigo(texto: str) -> tuple:
    for patron, codigo, comun in CODIGOS:
        if re.search(patron, texto, re.IGNORECASE):
            return codigo, comun
    raise ValueError(f"Pregunta abierta sin código: {texto[:90]!r}")


def _es_abierta(conv: Conversor, col: Columna) -> bool:
    if col.tipo == "abierta":
        return True
    reglas = [r for r in REGLAS[conv.d.colectivo] if r.encaja(col)]
    return bool(reglas) and reglas[0].accion == "descartar" and reglas[0].params.get("motivo") == "respuesta abierta"


def extraer(carpeta: Path) -> tuple:
    """Preguntas abiertas con sus respuestas, y las columnas de nombres que no se cargan (solo con su número)."""
    dic = Diccionario()
    preguntas: List[PreguntaAbierta] = []
    descartadas: List[Descartada] = []
    for d in DEFINICIONES:
        ruta = carpeta / d.fichero
        if not ruta.exists():
            continue
        t = leer(ruta)
        conv = Conversor(dic, d, t)
        # Las mismas reglas que la carga de 2025/26, para sacar de cada fila el grupo, las etapas o el segmento.
        plan = [(col, next(r for r in REGLAS[d.colectivo] if r.encaja(col))) for col in t.columnas
                if col.tipo != "abierta" and any(r.encaja(col) for r in REGLAS[d.colectivo])]
        columnas = [col for col in t.columnas if _es_abierta(conv, col)]
        for col, regla in plan:
            if regla.accion in ("nombre_profesor", "nombre_optativa"):
                descartadas.append(Descartada(d.codigo, col.cabecera, sum(1 for f in t.filas if t.valor(f, col.col))))
        propias: List[tuple] = []
        n_familias = 0
        for col in columnas:
            texto_col = col.texto if col.tipo != "abierta" else col.cabecera
            if NOMBRES.search(texto_col) or re.search(r"nombre de tu profesor", texto_col, re.IGNORECASE):
                descartadas.append(Descartada(d.codigo, texto_col, sum(1 for f in t.filas if t.valor(f, col.col))))
                continue
            if d.colectivo == "familias":
                codigo, texto = FAMILIAS[n_familias]
                n_familias += 1
                p = PreguntaAbierta(d.codigo, d.colectivo, 0, codigo, texto)
            else:
                codigo, _ = _codigo(texto_col)
                p = PreguntaAbierta(d.codigo, d.colectivo, 0, codigo, texto_col)
            propias.append((col, p))
        for fila in t.filas:
            r = Respuesta(abandonada=t.abandonada(fila))
            conv._fila(r, fila, plan)
            for col, p in propias:
                v = t.valor(fila, col.col)
                if v:
                    p.respuestas.append(Abierta(v, r.grupo, set(r.etapas), r.docente, r.antiguedad))
        for col, p in propias:
            p.orden = len([x for x in preguntas if x.cuestionario == d.codigo]) + 1
            preguntas.append(p)
    return preguntas, descartadas
