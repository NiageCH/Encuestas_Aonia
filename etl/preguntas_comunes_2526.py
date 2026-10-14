"""Preguntas comunes entre colectivos para el panel general (§7.1).

CANDIDATAS, PENDIENTES DE CONFIRMAR CON EL COLEGIO (pregunta abierta 5). Cada entrada une
preguntas del diccionario que miden lo mismo en distintos colectivos aunque cambie la
redacción ("el Centro" o "el Colegio", "estudiantes" o "alumnos"...). La carga las escribe en
public.pregunta_comun.
"""

from typing import List, Tuple

# (código común, texto para el panel, [códigos del diccionario])
COMUNES: List[Tuple[str, str, List[str]]] = [
    # Los tres colectivos
    ("ambiente", "Ambiente de respeto y convivencia", [
        "alu.aprendizaje_convivencia.el_ambiente_del_centro_es_de_respeto_y_convivencia",
        "fam.convivencia.el_ambiente_del_colegio_es_de_respeto_y_convivencia",
        "per.relaciones.el_ambiente_del_centro_es_de_respeto_y_convivencia"]),
    # Familias y personal
    ("competencia_profesorado", "Competencia profesional del profesorado", [
        "fam.profesorado.el_profesorado_demuestra_una_alta_competencia_profesional_en_la_docencia",
        "per.centro.el_profesorado_demuestra_una_alta_competencia_profesional_en_la_docencia"]),
    ("apoyo_profesorado", "Apoyo personal y académico del profesorado", [
        "fam.profesorado.el_profesorado_presta_apoyo_personal_y_academico_suficiente_a_los_alumnos",
        "per.centro.el_profesorado_presta_apoyo_personal_y_academico_suficiente_a_los_alumnos"]),
    ("atencion_individualizada", "Atención a las necesidades individualizadas", [
        "fam.convivencia.estoy_satisfecho_con_la_atencion_a_las_necesidades_individualizadas_de_mi_hijo",
        "per.centro.estoy_satisfecho_con_la_atencion_a_las_necesidades_individualizadas_de_mi_hijo"]),
    ("valores_eticos", "Valores éticos", [
        "fam.convivencia.considero_que_el_colegio_fomenta_valores_eticos_en_los_alumnos",
        "per.centro.considero_que_el_centro_fomenta_valores_eticos_en_los_alumnos"]),
    ("prepara_futuro", "El modelo educativo prepara para el futuro", [
        "fam.general.nuestro_modelo_educativo_prepara_a_los_alumnos_para_su_futuro_profesional_y_personal",
        "per.centro.nuestro_modelo_educativo_prepara_a_los_estudiantes_para_su_futuro_profesional_y_personal"]),
    ("mentalidad_internacional", "Mentalidad internacional y multicultural", [
        "fam.formacion.el_colegio_promueve_una_mentalidad_internacional_y_multicultural",
        "per.centro.el_colegio_fomenta_una_mentalidad_internacional_y_multicultural"]),
    ("innovacion", "Innovación", [
        "fam.ensenanza.el_colegio_es_innovador_y_promueve_la_innovacion_en_los_alumnos",
        "per.centro.el_colegio_es_innovador_y_fomenta_la_innovacion_en_los_alumnos"]),
    ("lectura", "Lectura", [
        "fam.formacion.el_colegio_promueve_la_lectura_en_sus_alumnos",
        "per.centro.el_colegio_promueve_la_lectura_en_sus_alumnos"]),
    ("artes", "Artes", [
        "fam.formacion.el_colegio_fomenta_las_artes_entre_sus_alumnos",
        "per.centro.el_colegio_fomenta_las_artes_en_sus_alumnos"]),
    ("musica", "Música", [
        "fam.formacion.el_colegio_impulsa_el_conocimiento_y_la_practica_musical_en_sus_alumnos",
        "per.centro.el_colegio_impulsa_el_conocimiento_y_la_practica_musical_en_sus_alumnos"]),
    ("competencias_digitales", "Competencias digitales", [
        "fam.ensenanza.el_colegio_favorece_las_competencias_digitales_en_sus_alumnos",
        "per.centro.el_colegio_favorece_las_competencias_digitales_en_sus_alumnos"]),
    ("cultura", "Cultura", [
        "fam.formacion.el_colegio_favorece_que_los_alumnos_adquieran_y_disfruten_el_valor_de_la_cultura",
        "per.centro.el_colegio_favorece_que_los_alumnos_adquieran_y_disfruten_el_valor_de_la_cultura"]),
    ("idiomas", "Enseñanza de idiomas", [
        "fam.ensenanza.el_colegio_cumple_las_expectativas_en_cuanto_a_la_ensenanza_de_los_idiomas",
        "per.centro.el_centro_cumple_las_expectativas_en_cuanto_a_la_ensenanza_de_los_idiomas"]),
    ("biblioteca_apoyo", "La Biblioteca apoya el aprendizaje", [
        "fam.formacion.la_biblioteca_del_colegio_es_un_importante_apoyo_al_aprendizaje_de_los_alumnos",
        "per.centro.la_biblioteca_del_centro_es_un_importante_apoyo_al_aprendizaje_de_los_alumnos"]),
    ("primera_opcion", "Acceso a la primera opción de carrera", [
        "fam.general.el_colegio_prepara_para_el_acceso_a_la_primera_opcion_de_carrera_de_los_alumnos",
        "per.centro.el_colegio_prepara_para_el_acceso_a_la_primera_opcion_de_carrera_de_los_alumnos"]),
    ("medioambiente", "Conciencia medioambiental", [
        "fam.convivencia.el_colegio_fomenta_la_conciencia_medioambiental",
        "per.centro.el_colegio_fomenta_la_consciencia_medioambiental_en_sus_alumnos"]),
    # Alumnos y familias
    ("recursos", "Los recursos usados favorecen el aprendizaje", [
        "alu.aprendizaje_convivencia.los_recursos_usados_favorecen_el_aprendizaje_de_los_alumnos",
        "fam.ensenanza.los_recursos_didacticos_usados_favorecen_el_aprendizaje_de_los_alumnos"]),
    ("comedor", "Comedor", ["alu.servicios.comedor", "fam.servicios.comedor"]),
    ("canasto", "Canasto", ["alu.servicios.canasto", "fam.servicios.canasto"]),
    ("biblioteca", "Biblioteca (servicio)", ["alu.servicios.biblioteca", "fam.servicios.biblioteca"]),
    ("limpieza", "Limpieza", ["alu.servicios.limpieza", "fam.servicios.limpieza"]),
    ("porteria", "Portería", ["alu.servicios.porteria", "fam.servicios.porteria"]),
    ("secretaria", "Secretaría Académica", ["alu.servicios.secretaria_academica", "fam.servicios.secretaria_academica"]),
    ("orientacion", "Servicio de Orientación", ["alu.servicios.servicio_de_orientacion", "fam.servicios.servicio_de_orientacion"]),
    ("transporte", "Transporte", ["alu.servicios.transporte_escolar", "fam.servicios.transporte"]),
]

COLECTIVO = {"alu": "alumnos", "fam": "familias", "per": "personal"}


def cargar_comunes(cur) -> int:
    """Reescribe public.pregunta_comun con la lista de candidatas. Devuelve las filas escritas."""
    cur.execute("select codigo_diccionario, id from public.pregunta")
    ids = dict(cur.fetchall())
    faltan = [c for _, _, codigos in COMUNES for c in codigos if c not in ids]
    if faltan:
        raise ValueError(f"Preguntas comunes que no están en el diccionario: {faltan}")
    cur.execute("delete from public.pregunta_comun")
    filas = [(comun, texto, COLECTIVO[c.split(".")[0]], ids[c]) for comun, texto, codigos in COMUNES for c in codigos]
    cur.executemany(
        "insert into public.pregunta_comun (codigo_comun, texto_es, colectivo, pregunta_id) values (%s, %s, %s, %s)", filas)
    return len(filas)
