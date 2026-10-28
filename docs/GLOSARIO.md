# Glosario de la plataforma

Términos aprobados en la revisión de lenguaje de Aonia (27 de octubre de 2026, con las propuestas aprobadas el mismo día). Se aplican a la web, los PDF, los CSV y las pantallas de la Fase 2: menús, títulos, filtros, leyendas de gráficos, avisos, textos explicativos, cabeceras de PDF y CSV y nombres de archivo.

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
| jefatura de departamento, jefatura de equipo | jefe de departamento, jefe de equipo | También «su jefatura» en los textos explicativos. |
| persona responsable directa | jefe o superior directo | El bloque de la encuesta se sigue llamando «Superiores». |

## Accesos y administración

| Usar | En lugar de |
|---|---|
| Accesos (menú y pantalla), Nuevo acceso | Usuarios |
| acceso, cuenta | usuario |
| Administración (rol), cuentas de administración | Administrador, administradores |
| Te damos la bienvenida | Bienvenida o bienvenido |

El código del rol (`administrador`) y la dirección de la pantalla (`#/usuarios`) no cambian: no se ven en la interfaz.

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

Tono institucional y descriptivo, sin interpretaciones que no salgan de los datos. Por ejemplo, no «sus resultados son muy distintos» ni «lo que opina»: se describe qué se mide («Valoración de cada docente por parte del alumnado»).

«Colegio», siempre con mayúscula cuando se refiere al CIS-SFP.

## Enunciados

- **CSV:** los enunciados de preguntas y opciones van exactamente como están guardados.
- **Web y PDF:** se muestran con mayúscula inicial, sin cambiar el texto guardado.

## Orden

«Aspectos con mayor y menor valoración»: primero «Mayor valoración» y después «Menor valoración», en la web, el PDF y el CSV.

## Mensajes del servidor

Los mensajes de error del servidor y de la función de accesos siguen el mismo glosario (por ejemplo, «Sin acceso a este profesor/a», «Solo para administración»). Los comprueba el test `supabase/tests/20_lenguaje_mensajes.sql`.

## Descargas protegidas

Textos fijos de la marca de agua, el pie de los PDF y la cabecera de los CSV (§7.7 de la especificación):

| Dónde | Texto |
|---|---|
| Marca de agua de los PDF | CONFIDENCIAL · Uso exclusivo del Colegio Internacional de Sevilla, San Francisco de Paula |
| Pie de cada página | Descargado por [nombre] el [dd/mm/aaaa] a las [hh:mm] · Código [código] |
| Asunto del PDF | Confidencial |
| Primera línea del CSV | Confidencial · Uso exclusivo del Colegio |
| Cabecera del CSV | Descargado por · Fecha de descarga · Código |

En Accesos, la pestaña se llama «Descargas» y la otra «Personas y actividad». Tipos de descarga: «Informe de profesor/a», «Informe de jefatura», «Informe de equipo», «Informe de dirección», «Vista en PDF», «CSV» y «ZIP de informes». El código se escribe siempre así: «Código 7KQ2-M9XD».

## Criterio de anonimato según el rol

Confirmado por escrito por Mark el (fecha pendiente) (§5.0 de la especificación):

| Término | Uso |
|---|---|
| «menos de 5» (marca) | Junto a la cifra de respuestas de un resultado que se ve con menos de 5 respuestas. Solo lo ven Dirección y administración. En CSV: «3 (menos de 5)». |
| «menos de 5» (oculto) | Para la coordinación y en la versión docente: el resultado no se muestra. Mismo texto, sin cifra. |
| Versión completa | Informe del profesor/a para Dirección y administración: todo, con la marca, y el detalle de cada pregunta en cada clase. Bajo el nombre: «Versión completa (Dirección y administración) · no entregar al docente». |
| Versión docente | Informe que recibe el docente, con el mínimo de 5: «Versión docente (la que recibe el docente)». |
| Detalle por clase | Sección de la versión completa: cada pregunta en cada clase (asignatura y grupo). |

## Respuestas abiertas y envío de informes

| Término | Uso |
|---|---|
| Respuestas abiertas | Entrada del menú y título de la pantalla. Lo que cada persona escribió, «tal cual». |
| «¿Qué echa en falta en el Colegio?» · «Comentarios» | Nombres comunes de las preguntas abiertas en la pantalla; cada cuestionario guarda su texto exacto. |
| Plan de Igualdad: necesidades que debería contener · medidas para promover la igualdad de oportunidades · otras sugerencias | Las tres preguntas abiertas del Plan de Igualdad (personal). |
| Envío al profesorado | Pestaña de Informes por persona (solo administración). |
| Enlace personal | El que recibe cada docente por correo; «caduca» a los 7 días; se puede «anular». |
| Apertura · descarga | Lo que se registra de cada enlace. |
| Modo de pruebas | Mientras no exista `encuestas@sfpaula.com`: los correos van a un correo de Niage, con «[PRUEBA]» en el asunto. |
| Destinatarios | Vista previa antes de enviar: «Se envía» o «Fuera: no tiene resultados del alumnado» / «Fuera: no tiene correo». |

Al docente se le trata de usted (correo y página del enlace).

## Tablas

Ninguna celda se parte palabra a palabra:

- las columnas tienen un ancho mínimo;
- los rangos («de 1 a 6», «9 y 10») no se separan, ni en la web ni en los PDF (`src/rangos.ts`); el CSV los escribe con espacios normales;
- en el móvil, las filas se apilan.
