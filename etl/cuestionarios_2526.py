"""Definición de los cuestionarios del curso 2025/26 y su conversión al modelo de datos.

Cada columna de cada fichero tiene que encajar en exactamente una regla: o se carga, o se
descarta con un motivo. Una columna sin regla detiene la carga.

Códigos del diccionario: "<colectivo>.<bloque>.<texto normalizado>". El bloque forma parte
del código porque hay ítems con el mismo texto en bloques distintos (por ejemplo, los diez
rasgos del perfil IB en "Unidades de indagación" y en "Programa TKS").
"""

from __future__ import annotations

import re
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Dict, List, Optional, Set, Tuple

from encuesta_facil import (Columna, Tabla, etapa_de_nivel, frase, leer, normalizar_grupo,
                            normalizar_texto, sin_acentos, slug)

CURSO = "2025/26"

# Escala de frecuencia (Nada a Total), igual en todos los ficheros. Se usa para columnas que
# solo traen etiqueta cuando el propio fichero no tiene pares valor y etiqueta de esa escala.
ESCALA_FRECUENCIA = {"Nada": 1, "Muy poco": 2, "Poco": 3, "Bastante": 4, "Mucho": 5, "Total": 6}
# Extremo de la escala de acuerdo que en personal solo aparece en columnas sin valor
# numérico; en el resto de ficheros siempre vale 1.
ESCALA_ACUERDO = {"Completamente en desacuerdo": 1}
ETIQUETAS_RESPALDO = {**ESCALA_FRECUENCIA, **ESCALA_ACUERDO}
NS_NC = "NS/NC"
# Etiqueta defectuosa de la exportación (columna "Artes Escénicas" de la matriz de
# reuniones de departamento): no es una respuesta y no se carga.
ETIQUETAS_INVALIDAS = {"Opción"}
OPCIONES_IGNORADAS = {"", "Otro (Por favor especifique)"}
# Redacciones distintas de la misma afirmación según el departamento: se unifican.
TEXTOS_EQUIVALENTES = {
    "Existe buena comunicación de arriba a abajo entre el Jefe del Dpto. y los Profesores":
        "Existe buena comunicación de arriba a abajo entre Jefe de Dpto. y Profesores",
    "Existe buena comunicación de abajo a arriba entre Profesores y Jefe del Dpto":
        "Existe buena comunicación de abajo a arriba entre Profesores y Jefe de Dpto",
}


# Modelo de salida ----------------------------------------------------------------------------

@dataclass
class Pregunta:
    codigo: str
    texto: str
    tipo: str                    # escala, recomendacion, seleccion_multiple
    escala_min: Optional[int] = None
    escala_max: Optional[int] = None
    escala_pendiente: bool = False


@dataclass
class Bloque:
    codigo: str
    nombre: str
    orden: int
    entra_en_media: bool


@dataclass
class PreguntaCuestionario:
    pregunta: str
    bloque: str
    orden: int
    por_asignatura: bool = False
    por_departamento: bool = False


@dataclass
class Item:
    pregunta: str
    valor: Optional[int]
    ns_nc: bool
    asignatura: Optional[str] = None
    departamento: Optional[str] = None


@dataclass
class Respuesta:
    abandonada: bool
    grupo: Optional[str] = None
    etapas: Set[str] = field(default_factory=set)
    docente: Optional[bool] = None
    antiguedad: Optional[str] = None
    items: List[Item] = field(default_factory=list)
    opciones: List[Tuple[str, str]] = field(default_factory=list)   # (pregunta, código de opción)
    tramo: Optional[str] = None      # personal: tramo de tutoría (solo para el Equipo de Individuación)
    # Alumnos: texto libre con el nombre del profesor por asignatura o de la optativa. Solo se
    # usa en memoria para atribuir la respuesta a un docente (atribucion_2526.py); nunca se carga.
    textos: Dict[str, str] = field(default_factory=dict)

    def tiene_datos(self) -> bool:
        return any(i.valor is not None for i in self.items) or bool(self.opciones)


@dataclass
class Cuestionario:
    codigo: str
    titulo: str
    colectivo: str
    etapa: Optional[str]
    fichero: str
    idioma: str = "es"
    bloques: Dict[str, Bloque] = field(default_factory=dict)
    preguntas_cuest: Dict[Tuple[str, Optional[str]], PreguntaCuestionario] = field(default_factory=dict)
    respuestas: List[Respuesta] = field(default_factory=list)
    filas: int = 0
    abandonadas: int = 0
    sin_datos: int = 0
    excluidas_sin_segmento: int = 0   # personal: no indican docente o antigüedad (§5)
    descartes: Counter = field(default_factory=Counter)
    avisos: Counter = field(default_factory=Counter)


class Diccionario:
    """Preguntas y opciones comunes a todos los cuestionarios del curso."""

    def __init__(self) -> None:
        self.preguntas: Dict[str, Pregunta] = {}
        self.textos: Dict[str, str] = {}                       # código -> texto normalizado
        self.opciones: Dict[str, Dict[str, str]] = defaultdict(dict)   # pregunta -> código -> texto

    def pregunta(self, codigo: str, texto: str, tipo: str, escala: Optional[Tuple[int, int]] = None,
                 pendiente: bool = False) -> str:
        texto = normalizar_texto(texto)
        p = self.preguntas.get(codigo)
        if p is None:
            self.preguntas[codigo] = Pregunta(codigo, texto, tipo, *(escala or (None, None)), pendiente)
            self.textos[codigo] = texto
        else:
            if (p.tipo, p.escala_min, p.escala_max) != (tipo, *(escala or (None, None))):
                raise ValueError(f"La pregunta {codigo} aparece con tipos o escalas distintos")
            if tipo != "seleccion_multiple" and self.textos[codigo].lower() != texto.lower():
                raise ValueError(f"Colisión de código {codigo}: {self.textos[codigo]!r} y {texto!r}")
        return codigo

    def opcion(self, pregunta: str, texto: str) -> str:
        texto = normalizar_texto(texto)
        codigo = slug(texto, 50)
        previo = self.opciones[pregunta].get(codigo)
        if previo is not None and previo.lower() != texto.lower():
            raise ValueError(f"Colisión de opción {pregunta}.{codigo}: {previo!r} y {texto!r}")
        self.opciones[pregunta].setdefault(codigo, texto)
        return codigo


# Reglas ----------------------------------------------------------------------------------

@dataclass
class Regla:
    patron: str
    accion: str
    params: dict = field(default_factory=dict)

    def encaja(self, col: Columna) -> bool:
        return re.search(self.patron, col.cabecera, re.IGNORECASE) is not None


def descartar(patron: str, motivo: str) -> Regla:
    return Regla(patron, "descartar", {"motivo": motivo})


def bloque(patron: str, codigo: str, nombre: str, escala=(1, 6), entra=True, **extra) -> Regla:
    return Regla(patron, "bloque", {"codigo": codigo, "nombre": nombre, "escala": escala, "entra": entra, **extra})


PATRON_ASIGNATURA = re.compile(
    r"^Para (?:la|las) asignaturas?(?: optativa)?(?: de)? (?P<asig>.+?)(?:,|\s+indica|\s+pincha)", re.IGNORECASE)

REGLAS_ALUMNOS = [
    Regla(r"curso y grupo|Elige tu grupo|En qué grupo de Y", "grupo"),
    descartar(r"^¿Vienes al Colegio|^¿Comes en el comedor|^¿Usas el servicio de canasto", "uso de servicios (acota a la persona)"),
    descartar(r"idioma que cursas|segundo idioma|nivel de inglés|materias? (que )?cursas|Marca TODAS las materias|Marca la materia",
              "materias e idiomas cursados (acota a la persona)"),
    Regla(r"nombre de la OPTATIVA", "nombre_optativa"),
    descartar(r"Indica la optativa|Plan Integral de Música|Diversificación Musical|Si cursas ESPAÑOL B",
              "optativas y programas cursados (acota a la persona)"),
    Regla(r"nombre de tu profesora? de", "nombre_profesor"),
    descartar(r"nombre de tu profesor", "nombre del profesor (texto libre)"),
    descartar(r"echas en falta|dejarnos un comentario", "respuesta abierta"),
    Regla(PATRON_ASIGNATURA.pattern, "profesorado"),
    bloque(r"UNIDADES DE INDAGACI", "unidades_indagacion", "Unidades de indagación"),
    bloque(r"programa TKS", "tks", "Programa TKS"),
    bloque(r"logrado desarrollar", "perfil_ib", "Perfil IB"),
    bloque(r"MINDFULNESS", "mindfulness", "Mindfulness"),
    bloque(r"ENCUENTROS CON EMPRENDEDORES", "encuentros", "Encuentros con emprendedores"),
    bloque(r"NARRACIÓN E IMPROVISACIÓN", "narracion", "Narración e improvisación"),
    bloque(r"PASIONES", "pasiones", "Pasiones"),
    bloque(r"IGNITE", "ignite", "Ignite!"),
    bloque(r"EUREKA", "eureka", "Eureka!"),
    bloque(r"procesos de autoevaluación", "autoevaluacion_ib", "Autoevaluación IB", escala=(1, 3), entra=False),
    bloque(r"^Piensa si estás de acuerdo|grado de acuerdo respecto a las siguientes afirmaciones",
           "aprendizaje_convivencia", "Aprendizaje y convivencia"),
    Regla(r"aspectos más importantes para ti|lo más importante", "seleccion",
          {"codigo": "alu.aspectos_importantes", "texto": "Aspectos más importantes para ti", "bloque": "aspectos_importantes",
           "nombre": "Aspectos más importantes"}),
    Regla(r"TRES aspectos valoras", "seleccion",
          {"codigo": "mas_valorado", "texto": "Lo más valorado del Colegio", "bloque": "mas_valorado", "nombre": "Lo más valorado"}),
    bloque(r"servicio", "servicios", "Servicios del colegio"),
    Regla(r"satisfacción general con el Colegio", "respuesta_escala",
          {"codigo": "alu.satisfaccion_general", "texto": "Grado de satisfacción general con el Colegio",
           "bloque": "satisfaccion_general", "nombre": "Satisfacción general", "escala": (1, 6), "pendiente": True}),
    Regla(r"cuánto te gusta el Colegio", "respuesta_escala",
          {"codigo": "alu.cuanto_te_gusta", "texto": "Cuánto te gusta el Colegio",
           "bloque": "satisfaccion_general", "nombre": "Satisfacción general", "escala": (1, 6), "pendiente": True}),
    Regla(r"recomendar", "recomendacion", {"bloque": "recomendacion"}),
]

REGLAS_PERSONAL = [
    descartar(r"indique su sexo", "sexo"),
    descartar(r"requisito previo legal a la realización del Plan de Igualdad", "Plan de Igualdad"),
    descartar(r"respuesta libre y no hay obligación", "respuesta abierta"),
    Regla(r"Si es Tutor", "tramo_tutoria"),
    descartar(r"niveles en los que imparta", "niveles en los que imparte (acota a la persona)"),
    descartar(r"echa en falta|añadir algún comentario", "respuesta abierta"),
    Regla(r"¿Es personal docente", "docente"),
    Regla(r"primer año trabajando", "antiguedad"),
    Regla(r"pertenencia a los diferentes Dpto", "departamentos",
          {"codigo": "reuniones_departamento", "nombre": "Reuniones de departamento"}),
    Regla(r"relacionadas con el PEP", "bloque_texto", {"codigo": "pep", "nombre": "PEP", "entra": False}),
    Regla(r"relacionadas con el PAI", "bloque_texto", {"codigo": "pai", "nombre": "PAI asignaturas", "entra": False}),
    Regla(r"perfil de la comunidad de aprendizaje", "bloque_texto",
          {"codigo": "perfil_ib", "nombre": "Perfil IB: grado de logro", "entra": False}),
    bloque(r"^Por favor, indique su grado de acuerdo con las siguientes afirmaciones:?$",
           "equipo_individualizacion", "Equipo de Individuación", entra=False),
    bloque(r"^Por favor valore su grado de acuerdo", "centro", "Valoración del centro"),
    bloque(r"^Condiciones de trabajo", "condiciones", "Condiciones de trabajo"),
    bloque(r"^Relaciones interpersonales", "relaciones", "Relaciones interpersonales"),
    bloque(r"^Superiores", "superiores", "Superiores"),
    bloque(r"^Puesto de trabajo", "puesto", "Puesto de trabajo"),
    bloque(r"^Satisfacción con el Colegio", "satisfaccion", "Satisfacción con el colegio"),
    Regla(r"recomendaría el Colegio como centro de trabajo", "recomendacion", {"bloque": "recomendacion"}),
    Regla(r"aspectos más importante", "seleccion",
          {"codigo": "per.aspectos_importantes", "texto": "Aspectos más importantes para usted", "bloque": "aspectos_importantes",
           "nombre": "Aspectos más importantes"}),
    Regla(r"tres aspectos que más valora", "seleccion",
          {"codigo": "mas_valorado", "texto": "Lo más valorado del Colegio", "bloque": "mas_valorado", "nombre": "Lo más valorado"}),
]

REGLAS_FAMILIAS = [
    Regla(r"indique en qué curso está su hijo", "etapas_familia"),
    Regla(r"Elija la respuesta que más se acerque", "familias_principal"),
]

# Bloques de familias: el cuestionario los trae todos bajo una sola cabecera; se asignan por
# el comienzo del texto del ítem.
BLOQUES_FAMILIAS = [
    ("ensenanza", "Enseñanza y modelo educativo", [
        "La formación académica teórica", "Los conocimientos prácticos y habilidades", "El Colegio cumple las expectativas en cuanto a la enseñanza",
        "Estoy satisfecho con la metodología didáctica", "Considero los programas del Bachillerato Internacional",
        "Estoy satisfecho con el estatus de Centro Extranjero", "Los recursos didácticos usados", "El Colegio es innovador",
        "El Colegio favorece las competencias digitales"]),
    ("formacion", "Formación integral", [
        "El Colegio promueve la lectura", "La Biblioteca del Colegio es un importante apoyo", "El Colegio fomenta las artes",
        "El Colegio impulsa el conocimiento y la práctica musical", "El Colegio favorece que los alumnos adquieran y disfruten",
        "El Colegio promueve una mentalidad internacional"]),
    ("profesorado", "Profesorado y tutoría", [
        "El Profesorado demuestra una alta competencia", "El Profesorado presta apoyo personal", "Estoy satisfecho con la labor tutorial"]),
    ("convivencia", "Convivencia, valores y actividades", [
        "El Colegio promueve hábitos saludables", "El Colegio fomenta la conciencia medioambiental", "El ambiente del Colegio es de respeto",
        "Estoy satisfecho con la atención a las necesidades individualizadas", "Considero que el Colegio fomenta valores éticos",
        "Las actividades complementarias", "Las actividades extralectivas"]),
    ("atencion", "Atención del equipo", [
        "La atención de los Vigilantes Educativos", "La atención recibida por parte del equipo de Dirección"]),
    ("general", "Valoración general del centro", [
        "El Colegio prepara para el acceso a la primera opción", "Nuestro modelo educativo prepara", "El Colegio satisface las expectativas",
        "El Colegio es un referente de la excelencia", "Mi hijo, habitualmente va contento", "En general, estoy satisfecho con el modelo educativo"]),
    ("comunicacion", "Comunicación y plataformas", [
        "La información accesible desde el Campus", "En general, estoy satisfecho con el cambio del Campus", "En general, estoy satisfecho con la nueva App",
        "Estoy satisfecho con la comunicación de las calificaciones", "En general, estoy satisfecho con las publicaciones",
        "Estoy satisfecho con las comunicaciones que recibo", "Reuniones individuales con familias"]),
    ("servicios", "Servicios", [
        "Servicio de Orientación", "Portería", "Papelería", "Transporte", "Comedor", "Canasto", "Cafetería", "Biblioteca",
        "Servicio de enfermería", "Secretaría Académica", "Administración (ventanilla)", "Limpieza", "Mantenimiento de las instalaciones"]),
]

ETAPAS_FAMILIAS = {"Crèche": "infantil", "Daycare": "infantil", "EPS": "infantil", "PS": "infantil"}


def etapa_de_curso_familia(texto: str) -> str:
    if texto in ETAPAS_FAMILIAS:
        return ETAPAS_FAMILIAS[texto]
    if re.match(r"^(PK|K)\b", texto):
        return "infantil"
    m = re.match(r"^(Y\d{1,2})\b", texto)
    if m:
        return etapa_de_nivel(m.group(1))
    raise ValueError(f"Curso de familias sin etapa: {texto!r}")


# Ficheros del curso -------------------------------------------------------------------------

@dataclass
class Definicion:
    fichero: str
    codigo: str
    titulo: str
    colectivo: str
    etapa: Optional[str]
    nivel_grupo: Optional[str] = None      # para ficheros cuyo grupo es solo la letra
    escala_recomendacion: Tuple[int, int] = (0, 10)
    idioma: str = "es"


DEFINICIONES = [
    Definicion("2526_Y2Y5.csv", "ALU_Y2Y5", "Primaria (Y2 a Y5)", "alumnos", "primaria", escala_recomendacion=(1, 10)),
    Definicion("2526_Y6Y9.csv", "ALU_Y6Y9", "PAI asignaturas (Y6 a Y9)", "alumnos", "pai"),
    Definicion("2526_Y6Y10.csv", "ALU_Y6Y10", "PAI competencias (Y6 a Y10)", "alumnos", "pai"),
    Definicion("2526_Y10.csv", "ALU_Y10", "PAI asignaturas (Y10)", "alumnos", "pai", nivel_grupo="Y10"),
    Definicion("2526_Y11.csv", "ALU_Y11", "Bachillerato (Y11)", "alumnos", "bachillerato", nivel_grupo="Y11"),
    Definicion("2526_Y12.csv", "ALU_Y12", "Bachillerato (Y12)", "alumnos", "bachillerato", nivel_grupo="Y12"),
    Definicion("Cliente_2526.xlsx", "FAM", "Familias", "familias", None, escala_recomendacion=(1, 10)),
    Definicion("Empleado_2526.csv", "PER", "Personal", "personal", None, escala_recomendacion=(1, 10)),
    # El cuestionario de personal en inglés se une al mismo cuestionario "PER" con
    # idioma "en". Falta el fichero y la correspondencia de sus textos con el diccionario
    # (TEXTOS_PERSONAL_EN). Hasta entonces, si el fichero aparece, la carga se detiene.
    Definicion("Employees_2526.csv", "PER", "Personal", "personal", None, escala_recomendacion=(1, 10), idioma="en"),
]

# Texto en inglés de la exportación -> texto en español del cuestionario de personal. Se
# rellenará cuando llegue el fichero; las preguntas se mapean al mismo código del diccionario.
TEXTOS_PERSONAL_EN: Dict[str, str] = {}

REGLAS = {"alumnos": REGLAS_ALUMNOS, "familias": REGLAS_FAMILIAS, "personal": REGLAS_PERSONAL}
PREFIJO = {"alumnos": "alu", "familias": "fam", "personal": "per"}


# Conversión -------------------------------------------------------------------------------

class Conversor:
    def __init__(self, dic: Diccionario, d: Definicion, t: Tabla) -> None:
        self.dic, self.d, self.t = dic, d, t
        self.c = Cuestionario(d.codigo, d.titulo, d.colectivo, d.etapa, d.fichero, d.idioma)
        self.etiquetas = self._etiquetas_del_fichero()

    # Correspondencia etiqueta -> valor sacada de los pares "Valor" + etiqueta del fichero.
    def _etiquetas_del_fichero(self) -> Dict[str, int]:
        pares: Dict[str, Counter] = defaultdict(Counter)
        for col in self.t.columnas:
            if col.tipo != "valor":
                continue
            for f in self.t.filas:
                v, e = self.t.valor(f, col.col), self.t.valor(f, col.col_etiqueta)
                if v and e and e != NS_NC:
                    pares[e][int(v)] += 1
        mapa = {}
        for e, cuenta in pares.items():
            if len(cuenta) > 1:
                raise ValueError(f"{self.t.origen}: la etiqueta {e!r} tiene varios valores {dict(cuenta)}")
            mapa[e] = next(iter(cuenta))
        return mapa

    def _bloque(self, codigo: str, nombre: str, entra: bool) -> str:
        if codigo not in self.c.bloques:
            self.c.bloques[codigo] = Bloque(codigo, nombre, len(self.c.bloques) + 1, entra)
        return codigo

    def _pc(self, pregunta: str, bloque: str, por_asignatura=False, por_departamento=False) -> None:
        clave = (pregunta, None)
        if clave not in self.c.preguntas_cuest:
            self.c.preguntas_cuest[clave] = PreguntaCuestionario(
                pregunta, bloque, len(self.c.preguntas_cuest) + 1, por_asignatura, por_departamento)
        elif self.c.preguntas_cuest[clave].bloque != bloque:
            raise ValueError(f"{self.t.origen}: la pregunta {pregunta} aparece en dos bloques")

    def _codigo(self, bloque: str, texto: str) -> str:
        return f"{PREFIJO[self.d.colectivo]}.{bloque}.{slug(texto, 120)}"

    def convertir(self) -> Cuestionario:
        reglas = REGLAS[self.d.colectivo]
        plan: List[Tuple[Columna, Regla]] = []
        for col in self.t.columnas:
            if col.tipo == "abierta":
                self.c.descartes["respuesta abierta"] += 1
                continue
            encajan = [r for r in reglas if r.encaja(col)]
            if not encajan:
                raise ValueError(f"{self.t.origen}: columna {col.col} sin regla: {col.cabecera[:90]!r}")
            plan.append((col, encajan[0]))

        self.c.filas = len(self.t.filas)
        for fila in self.t.filas:
            r = Respuesta(abandonada=self.t.abandonada(fila))
            self._fila(r, fila, plan)
            self.c.abandonadas += r.abandonada
            if not r.tiene_datos():
                self.c.sin_datos += 1
            elif self.d.colectivo == "personal" and (r.docente is None or r.antiguedad is None):
                # Quien no indica su segmento formaría una parte de una sola persona: el total
                # menos los segmentos la dejaría al descubierto. Se excluye de personal.
                self.c.excluidas_sin_segmento += 1
            else:
                self.c.respuestas.append(r)
        return self.c

    def _fila(self, r: Respuesta, fila: List[str], plan: List[Tuple[Columna, Regla]]) -> None:
        corrida_familias = 0     # en familias: 0 = aspectos más importantes, 1 = lo más valorado
        for col, regla in plan:
            v = self.t.valor(fila, col.col)
            a = regla.accion
            if a == "descartar":
                if fila is self.t.filas[0]:
                    self.c.descartes[regla.params["motivo"]] += 1
            elif a == "grupo":
                g = normalizar_grupo(v, self.d.nivel_grupo)
                if g and etapa_de_nivel(g.split()[0]) != self.d.etapa:
                    raise ValueError(f"{self.t.origen}: grupo {g} fuera de la etapa {self.d.etapa}")
                r.grupo = g
            elif a == "profesorado":
                asig = frase(PATRON_ASIGNATURA.search(col.cabecera).group("asig"))
                self._valoracion(r, fila, col, "profesorado", "Profesorado", (1, 6), True, asignatura=asig,
                                 codigo=f"alu.profesorado.{slug(col.texto, 120)}")
            elif a == "bloque":
                p = regla.params
                self._valoracion(r, fila, col, p["codigo"], p["nombre"], p["escala"], p["entra"])
            elif a == "respuesta_escala":
                p = regla.params
                self._bloque(p["bloque"], p["nombre"], True)
                codigo = self.dic.pregunta(p["codigo"], p["texto"], "escala", p["escala"], p.get("pendiente", False))
                self._pc(codigo, p["bloque"])
                if v:
                    r.items.append(Item(codigo, self._entero(v, p["escala"], codigo), False))
            elif a == "recomendacion":
                self._recomendacion(r, v)
            elif a == "seleccion":
                p = regla.params
                self._seleccion(r, fila, col, p["codigo"], p["texto"], p["bloque"], p["nombre"])
            elif a == "nombre_profesor":
                m = re.search(r"profesora? de (?P<asig>.+?):?\s*$", col.cabecera, re.IGNORECASE)
                if v.strip():
                    r.textos[sin_acentos(m.group("asig")).lower().strip()] = v
                if fila is self.t.filas[0]:
                    self.c.descartes["nombre del profesor (solo para atribuir; el texto no se carga)"] += 1
            elif a == "nombre_optativa":
                if v.strip():
                    r.textos["optativa"] = v
                if fila is self.t.filas[0]:
                    self.c.descartes["nombre de la optativa (solo para atribuir; el texto no se carga)"] += 1
            elif a == "tramo_tutoria":
                if v.strip() and col.texto != "Ninguno":
                    t = tramo_de_nivel(col.texto)
                    r.tramo = t if r.tramo in (None, t) else "varios"
                if fila is self.t.filas[0]:
                    self.c.descartes["nivel de tutoría (solo se carga el tramo, para el Equipo de Individuación)"] += 1
            elif a == "docente":
                r.docente = {"Sí": True, "No": False}.get(v)
            elif a == "antiguedad":
                r.antiguedad = {"Sí": "primer_ano", "No": "mas_de_un_ano"}.get(v)
            elif a == "bloque_texto":
                p = regla.params
                self._valoracion_texto(r, col, v, p["codigo"], p["nombre"], p["entra"])
            elif a == "departamentos":
                m = re.match(r"^(?P<texto>.+?)\s+-\s+Dpto\.\s*(?P<dep>.+)$", col.texto)
                if not m:
                    raise ValueError(f"{self.t.origen}: columna {col.col} sin departamento: {col.texto!r}")
                self._valoracion_texto(r, col, v, regla.params["codigo"], regla.params["nombre"], False,
                                       texto=m.group("texto"), departamento=m.group("dep").strip())
            elif a == "etapas_familia":
                if v:
                    r.etapas.add(etapa_de_curso_familia(col.texto))
            elif a == "familias_principal":
                if col.tipo == "valor":
                    codigo_b, nombre_b = self._bloque_familias(col.texto)
                    self._valoracion(r, fila, col, codigo_b, nombre_b, (1, 6), True)
                elif col.tipo == "respuesta":
                    if self._es_numerica(col):
                        self._recomendacion(r, v)
                    elif fila is self.t.filas[0]:
                        self.c.descartes["pregunta sin texto en la exportación (familias)"] += 1
                elif col.tipo == "opcion":
                    if col.texto == "Otro (Por favor especifique)":
                        corrida_familias += 1
                        continue
                    if corrida_familias == 0:
                        self._seleccion(r, fila, col, "fam.aspectos_importantes", "Aspectos más importantes para usted",
                                        "aspectos_importantes", "Aspectos más importantes")
                    else:
                        self._seleccion(r, fila, col, "mas_valorado", "Lo más valorado del Colegio",
                                        "mas_valorado", "Lo más valorado")
            else:
                raise ValueError(f"Acción desconocida: {a}")

    def _es_numerica(self, col: Columna) -> bool:
        vals = [self.t.valor(f, col.col) for f in self.t.filas]
        vals = [v for v in vals if v]
        return bool(vals) and all(re.fullmatch(r"\d+", v) for v in vals)

    def _bloque_familias(self, texto: str) -> Tuple[str, str]:
        t = normalizar_texto(texto)
        for codigo, nombre, comienzos in BLOQUES_FAMILIAS:
            if any(t.startswith(c) for c in comienzos):
                return codigo, nombre
        raise ValueError(f"Ítem de familias sin bloque: {texto!r}")

    def _entero(self, v: str, escala: Tuple[int, int], codigo: str) -> int:
        n = int(v)
        if not escala[0] <= n <= escala[1]:
            raise ValueError(f"{self.t.origen}: valor {n} fuera de la escala {escala} en {codigo}")
        return n

    def _valoracion(self, r: Respuesta, fila: List[str], col: Columna, bloque: str, nombre: str,
                    escala: Tuple[int, int], entra: bool, asignatura: Optional[str] = None,
                    codigo: Optional[str] = None) -> None:
        self._bloque(bloque, nombre, entra)
        codigo = self.dic.pregunta(codigo or self._codigo(bloque, col.texto), col.texto, "escala", escala)
        self._pc(codigo, bloque, por_asignatura=asignatura is not None)
        v = self.t.valor(fila, col.col)
        if not v:
            return
        etiqueta = self.t.valor(fila, col.col_etiqueta)
        if etiqueta == NS_NC:
            r.items.append(Item(codigo, None, True, asignatura=asignatura))
        else:
            r.items.append(Item(codigo, self._entero(v, escala, codigo), False, asignatura=asignatura))

    def _valoracion_texto(self, r: Respuesta, col: Columna, etiqueta: str, bloque: str, nombre: str, entra: bool,
                          texto: Optional[str] = None, departamento: Optional[str] = None) -> None:
        texto = normalizar_texto(texto or col.texto)
        texto = TEXTOS_EQUIVALENTES.get(texto, texto)
        self._bloque(bloque, nombre, entra)
        codigo = self.dic.pregunta(self._codigo(bloque, texto), texto, "escala", (1, 6))
        self._pc(codigo, bloque, por_departamento=departamento is not None)
        if not etiqueta:
            return
        if etiqueta in ETIQUETAS_INVALIDAS:
            self.c.avisos[f"etiqueta inválida {etiqueta!r} en {bloque} (no se carga)"] += 1
            return
        if etiqueta == NS_NC:
            r.items.append(Item(codigo, None, True, departamento=departamento))
            return
        valor = self.etiquetas.get(etiqueta, ETIQUETAS_RESPALDO.get(etiqueta))
        if valor is None:
            raise ValueError(f"{self.t.origen}: etiqueta desconocida {etiqueta!r} en {bloque}")
        r.items.append(Item(codigo, valor, False, departamento=departamento))

    def _recomendacion(self, r: Respuesta, v: str) -> None:
        escala = self.d.escala_recomendacion
        sufijo = "" if escala == (0, 10) else f"_{escala[0]}a{escala[1]}"
        codigo = self.dic.pregunta(f"{PREFIJO[self.d.colectivo]}.recomendacion{sufijo}",
                                   "Grado en que recomendaría el Colegio", "recomendacion", escala)
        self._bloque("recomendacion", "Recomendación", False)
        self._pc(codigo, "recomendacion")
        if v:
            r.items.append(Item(codigo, self._entero(v, escala, codigo), False))

    def _seleccion(self, r: Respuesta, fila: List[str], col: Columna, codigo: str, texto: str,
                   bloque: str, nombre: str) -> None:
        if col.texto in OPCIONES_IGNORADAS:
            if fila is self.t.filas[0]:
                self.c.descartes["opción «Otro» y su texto libre"] += 1
            return
        self._bloque(bloque, nombre, False)
        self.dic.pregunta(codigo, texto, "seleccion_multiple")
        self._pc(codigo, bloque)
        op = self.dic.opcion(codigo, col.texto)
        v = self.t.valor(fila, col.col)
        if v:
            if normalizar_texto(v) != normalizar_texto(col.texto):
                raise ValueError(f"{self.t.origen}: opción con texto inesperado en la columna {col.col}")
            r.opciones.append((codigo, op))


def tramo_de_nivel(nivel: str) -> str:
    """Nivel de tutoría → tramo del Equipo de Individuación."""
    if nivel in ("EPS", "PS", "PK", "K"):
        return "infantil"
    n = int(nivel[1:])
    return "y1_y5" if n <= 5 else "y6_y9" if n <= 9 else "y10_y12"


def convertir_todo(carpeta: Path) -> Tuple[Diccionario, List[Cuestionario]]:
    dic = Diccionario()
    salida: List[Cuestionario] = []
    for d in DEFINICIONES:
        ruta = carpeta / d.fichero
        if not ruta.exists():
            if d.idioma == "en":
                continue
            raise FileNotFoundError(f"Falta {ruta}")
        if d.idioma == "en" and not TEXTOS_PERSONAL_EN:
            raise NotImplementedError(
                f"{d.fichero}: falta la correspondencia de textos en inglés (TEXTOS_PERSONAL_EN)")
        salida.append(Conversor(dic, d, leer(ruta)).convertir())
    return dic, salida
