"""Qué preguntas van en los informes de tutoría y de servicios de 2025/26 (especificación §7.12 y §7.13).

Solo códigos del diccionario de preguntas (los mismos de etl/cuestionarios_2526.py): ningún dato del Colegio.
Lo carga etl/cargar_informes_2526.py. Para otro curso, se copia este fichero y se ajustan los códigos.
"""

from __future__ import annotations

# Tutoría ---------------------------------------------------------------------------------------------------------------
# «grupo»: lo que el alumnado de cada grupo dice de su tutor/a (cada pregunta, en los cuestionarios en los que está).
# «colegio»: la labor tutorial según las familias y el personal, que no traen grupo: solo como referencia del Colegio
# (decisión de Mark del 11/11/2026).
TUTORIA_GRUPO = [
    "alu.aprendizaje_convivencia.el_tutor_atiende_bien_las_necesidades_de_nuestra_clase",
    "alu.aprendizaje_convivencia.el_tutor_ayuda_al_mantenimiento_de_un_buen_ambiente_en_la_clase_a_traves_del_refuerzo_de_los_valores_respeto",
    "alu.aprendizaje_convivencia.mi_tutor_es_amable_y_atiende_bien_a_nuestra_clase",
]
TUTORIA_COLEGIO = [
    "fam.profesorado.estoy_satisfecho_con_la_labor_tutorial",
    "per.centro.la_labor_tutorial_es_muy_satisfactoria",
]

# Servicios -------------------------------------------------------------------------------------------------------------
# (código, nombre, preguntas del bloque de servicios de cada encuesta, preguntas propias del servicio en otros bloques).
# Cada encuesta llama a algunos servicios de otra forma: aquí se juntan («Enfermería» y «Servicio de enfermería»,
# «Transporte escolar» y «Transporte», «Mantenimiento» y «Mantenimiento de las instalaciones», «Administración» y
# «Administración (ventanilla)»). «Atención al cliente» (alumnado de PAI) va aparte, a falta de que el Colegio diga si
# es el mismo servicio que Administración.
SERVICIOS: list[tuple[str, str, list[str], list[str]]] = [
    ("administracion", "Administración",
     ["alu.servicios.administracion", "fam.servicios.administracion_ventanilla"], []),
    ("atencion_cliente", "Atención al cliente", ["alu.servicios.atencion_al_cliente"], []),
    ("biblioteca", "Biblioteca", ["alu.servicios.biblioteca", "fam.servicios.biblioteca"], [
        "alu.aprendizaje_convivencia.la_atencion_en_la_biblioteca_es_buena",
        "alu.aprendizaje_convivencia.en_la_biblioteca_me_atienden_bien",
        "alu.aprendizaje_convivencia.en_la_biblioteca_me_motivan_a_leer_y_me_ayudan_a_buscar_informacion",
        "alu.aprendizaje_convivencia.en_la_biblioteca_se_puede_estudiar_y_trabajar_en_un_ambiente_agradable",
        "alu.aprendizaje_convivencia.el_personal_de_biblioteca_corrige_nuestros_comportamientos_inadecuados",
        "fam.formacion.la_biblioteca_del_colegio_es_un_importante_apoyo_al_aprendizaje_de_los_alumnos",
        "per.centro.la_biblioteca_del_centro_es_un_importante_apoyo_al_aprendizaje_de_los_alumnos",
    ]),
    ("cafeteria", "Cafetería", ["fam.servicios.cafeteria"], []),
    ("canasto", "Canasto", ["alu.servicios.canasto", "fam.servicios.canasto"], []),
    ("comedor", "Comedor", ["alu.servicios.comedor", "fam.servicios.comedor"], []),
    ("enfermeria", "Enfermería", ["alu.servicios.enfermeria", "fam.servicios.servicio_de_enfermeria"], []),
    ("limpieza", "Limpieza", ["alu.servicios.limpieza", "fam.servicios.limpieza"], []),
    ("mantenimiento", "Mantenimiento",
     ["alu.servicios.mantenimiento", "fam.servicios.mantenimiento_de_las_instalaciones"], []),
    ("papeleria", "Papelería", ["fam.servicios.papeleria"], []),
    ("porteria", "Portería", ["alu.servicios.porteria", "fam.servicios.porteria"], []),
    ("secretaria_academica", "Secretaría Académica",
     ["alu.servicios.secretaria_academica", "fam.servicios.secretaria_academica"], []),
    ("orientacion", "Servicio de Orientación",
     ["alu.servicios.servicio_de_orientacion", "fam.servicios.servicio_de_orientacion"], [
        "alu.aprendizaje_convivencia.las_actividades_de_orientacion_vocacional_sesiones_grupales_entrevistas_individuales_voluntarias_prueba_especifica_y",
        "alu.aprendizaje_convivencia.las_actividades_de_orientacion_vocacional_sesiones_grupales_entrevistas_individuales_voluntarias_y_feria_de",
        "per.centro.el_servicio_de_orientacion_presta_un_gran_apoyo_a_los_docentes_en_sus_funciones",
    ]),
    ("transporte", "Transporte escolar", ["alu.servicios.transporte_escolar", "fam.servicios.transporte"], []),
    ("vigilantes", "Vigilantes educativos", ["alu.servicios.vigilantes_educativos"], []),
]
