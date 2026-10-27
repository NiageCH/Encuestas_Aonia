# Glosario de la plataforma

Términos aprobados en la revisión de lenguaje de Aonia (octubre de 2026). Se aplican a la web, los PDF, los CSV y las pantallas de la Fase 2: menús, títulos, filtros, leyendas de gráficos, avisos, textos explicativos, cabeceras de PDF y CSV y nombres de archivo.

**No se aplican a los enunciados de las preguntas**, que se muestran tal como están en los cuestionarios.

El test `src/glosario.test.ts` revisa todos los textos de `I18N.es` y avisa si aparece un término descartado. La lista de términos descartados está en `src/glosario.ts`. Si cambia este glosario, hay que cambiarla también.

## Colectivos y personas

Mejor siempre el colectivo que la barra.

| Usar | En lugar de | Notas |
|---|---|---|
| alumnado | alumnos | Colectivo. «Alumno/a» solo en singular, cuando no haya otra forma. |
| profesorado | profesores | Colectivo. En plural también vale «docentes». |
| profesor/a | profesor | En singular, por ejemplo «Informe del profesor/a». Si la frase lo permite, «docente». |
| profesorado tutor | tutores | |
| personal | | Cuando incluye a docentes y no docentes. |
| personal no docente | no docentes | |
| jefe o jefa | jefe | Solo en los textos explicativos. El nombre del cargo («jefe de departamento», «jefe de equipo») no cambia. |

## Indicadores

| Usar | En lugar de |
|---|---|
| Aspectos con mayor y menor valoración | Puntos fuertes y de mejora |
| Mayor valoración | Puntos fuertes |
| Menor valoración | Puntos de mejora |
| Aspectos más destacados | Lo más valorado |
| Aspectos menos destacados | Lo menos elegido |
| Comparación de indicadores comunes entre colectivos | Comparación de lo que tienen en común |
| Diferencias entre respuestas favorables y desfavorables a la recomendación | En qué se diferencian quienes no recomendarían el Colegio |

En las notas se distinguen siempre dos tipos de resultado:

- **Resultados de valoración:** medias de 1 a 6.
- **Frecuencia de selección:** % de personas que eligen el aspecto entre sus tres opciones.

## Recomendación

| Usar | En lugar de |
|---|---|
| Respuestas favorables (9 y 10) | Sí, con entusiasmo; promotores |
| Respuestas neutras (7 y 8) | Neutral; neutros |
| Respuestas desfavorables (6 o menos) | No; detractores |

El rango es el de la escala: en las de 0 a 10 y de 1 a 10, «6 o menos» vale para las dos.

## Expresiones

| Usar | En lugar de |
|---|---|
| Selecciona un colectivo para consultar sus resultados detallados. | Entra en cada una para ver el detalle. |

Tono institucional y descriptivo, sin interpretaciones que no salgan de los datos.

## Enunciados

- **CSV:** los enunciados de preguntas y opciones van exactamente como están guardados.
- **Web y PDF:** se muestran con mayúscula inicial, sin cambiar el texto guardado.

## Tablas

Ninguna celda se parte palabra a palabra:

- las columnas tienen un ancho mínimo;
- los rangos («de 1 a 6», «9 y 10») no se separan;
- en el móvil, las filas se apilan.
