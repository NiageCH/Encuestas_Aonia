# Especificación · Plataforma de encuestas de satisfacción CIS-SFP

Versión 3 · 13 de octubre de 2026. Fase 1. Términos según el glosario (`docs/GLOSARIO.md`, revisión de lenguaje del 27/10/2026); los identificadores técnicos (`alumnos`, `administrador`…) no cambian. Cambios respecto a la versión 2: respuestas abandonadas (§2), etapas de familias, bloques de personal y escalas con texto (§2 y §4), etapas solapadas y reuniones de departamento (§5), coordinación y media del Colegio (§6).

---

## 1. Alcance por fases

| Fase | Alcance |
|---|---|
| **1 (ahora)** | Resultados 2025/26 del alumnado, las familias y el personal; accesos y roles; panel general con preguntas comunes; vista e informes PDF por profesor/a y por responsable |
| 2 | Gestión y publicación de encuestas propias: cuestionarios, asignación, enlace y QR, respuestas directas a la base de datos (mockup `referencia/mockups/Mockup_Encuestas_6_admin_encuestas.png`) |
| 3 | Histórico de todos los cursos y comparativa entre cursos |

Para que las fases 2 y 3 se construyan encima, el modelo de la Fase 1 debe cumplir tres cosas:
- preguntas con código estable (diccionario);
- el curso como dimensión en todas las tablas;
- cuestionarios versionados por curso.

---

## 2. Fuentes de datos (curso 2025/26)

Origen: SharePoint del Colegio, sitio `sfpaula`, biblioteca `VdAE/Encuestas`. Rodrigo descarga los ficheros a `datos_locales/fuentes/`.

| Encuesta | Ficheros y cuestionarios | Notas |
|---|---|---|
| Alumnado | 6 cuestionarios: Primaria (Y2 a Y5), PAI asignaturas (Y6 a Y9), PAI competencias (Y6 a Y10), PAI asignaturas (Y10), Bachillerato (Y11), Bachillerato (Y12) | **Cada respuesta trae el grupo** (curso y letra, por ejemplo "Y9 A"). El bloque de profesorado se repite por asignatura. |
| Familias | 1 cuestionario (`Cliente_2526.xlsx`) | La familia marca el curso de cada hijo (selección múltiple), así que **una respuesta puede tener varias etapas**. Solo se guarda la etapa, no el curso. |
| Personal | Español (`Empleado_2526.csv`) e inglés (fichero Employees, pendiente) | Se unen en un solo conjunto. Segmentos: docente o no docente, antigüedad (primer año o más). **No se carga el sexo ni el bloque del Plan de Igualdad.** El fichero **no trae departamento ni equipo** de cada persona (§7.3). |

### Formato de Encuesta Fácil
- CSV o XLSX. Antes de los datos hay filas de metadatos, una fila con el **texto de la pregunta** y otra con la **opción o subtítulo** ("Respuesta", nombre de la asignatura…). Localízalas por contenido, no por posición.
- Cada pregunta de valoración tiene una columna con el **valor numérico** y otra con la etiqueta. Se usa el valor.
- **Escala general de 1 a 6.** NS/NC se reconoce **por su etiqueta "NS/NC"**, no por un número fijo: suele ser el 7, pero en la autoevaluación IB de Y12 es el 4 (su escala real es de 1 a 3). No cuenta en la media y se guarda como NS/NC.
- **Etiquetas:** su significado cambia entre ficheros ("Insatisfecho" es 2 en el alumnado y 3 en familias). Las columnas que solo traen etiqueta, sin valor numérico (en personal: PEP, PAI, Perfil IB y reuniones de departamento), se convierten con la correspondencia etiqueta y valor **del mismo fichero**; una etiqueta desconocida detiene la carga.
- **Satisfacción general (alumnado):** una sola columna con valores de 1 a 6. El fichero no indica la escala; se trata como 1 a 6 y se marca "pendiente de confirmar".
- **Recomendación:** de 0 a 10 en el alumnado, salvo Primaria (de 1 a 10); de 1 a 10 en familias y personal.
- **Autoevaluación IB (Bachillerato Y12):** escala de 1 a 3 ("En desarrollo", "Desarrollada", "Muy desarrollada") más NS/NC, que el fichero codifica como 4. No entra en medias generales. El prototipo contó ese 4 como valoración: sus medias de este bloque no son comparables.
- **Respuestas del alumnado sin grupo:** algunas respuestas no indican grupo. Cuentan en el total del cuestionario y nunca forman un grupo propio.
- **«Aspectos más destacados»:** selección múltiple, hasta tres aspectos por persona, con una lista de opciones común a los tres colectivos.
- **Preguntas duplicadas:** en profesorado aparecen preguntas con redacción casi igual (por ejemplo con "..." delante, o con "trabajdo" y "trabajado"). Se unifican en el diccionario.
- **Nombres del profesorado:** los ficheros casi nunca los traen. La relación docente, asignatura y grupo viene del Excel del Colegio (§7.2).
- **Se descartan siempre:** identificador de respuesta, fechas y horas, IP, correo, nombre y apellidos, campos libres y parámetros de usuario, los nombres del profesorado y de la optativa, sexo, las preguntas cerradas del Plan de Igualdad, y datos que acotan a la persona sin estar en el alcance (nivel de tutoría y niveles en que imparte, segundo idioma, optativa, uso de transporte, comedor y canasto, curso de cada hijo). Las respuestas abiertas se cargan aparte, tal cual y solo para Dirección y administración (§7.9).
- **Respuestas abandonadas:**
  - **Se cargan**, con las preguntas que la persona sí contestó. La columna "Abandonado" solo sirve para contarlas.
  - **n = personas con al menos una valoración válida** (u opción marcada) en ese conjunto.
  - El número de abandonadas se guarda por cuestionario como dato informativo ("incluye X respuestas incompletas").
  - Ejemplos: Primaria tiene 280 respuestas, de las que 52 están abandonadas; familias, 72 con 4 abandonadas; personal en español, 77 con 4 abandonadas.

### Validación de la carga
Los valores de control están en `datos_locales/validacion_2526.md` (fuera de git), junto con los agregados completos en `datos_locales/referencia_agregados_2526.json`. **No se avanza del paso de ETL hasta que las RPC devuelvan esos valores** con una tolerancia de ±0,01 en medias y exactos en recuentos.

---

## 3. Cálculos

Estas reglas son las que usó el prototipo que produjo los valores de control.

- **Media de una pregunta:** media de todas las valoraciones válidas de esa pregunta, sin contar NS/NC.
- **Media de un bloque o dimensión, de una asignatura, del profesorado y "satisfacción media":**
  - es la **media agrupada** de todas las valoraciones válidas que la componen: cada valoración cuenta una vez;
  - es equivalente a la media de las medias de las preguntas ponderada por su n;
  - el prototipo publicó el bloque de profesorado con otra fórmula (media de las asignaturas ponderada por personas). La brecha es como mucho de 0,011 y solo cambia la cifra redondeada de un cuestionario (detalle en `datos_locales/validacion_2526.md`); se mantiene la media agrupada;
  - **no** es la media de las medias por persona.
- **"Satisfacción media" global:** excluye los bloques con escala distinta de 1 a 6 (Perfil IB en personal y Autoevaluación IB).
- **Media de un grupo** (por ejemplo, profesorado de Y9 A): todas las valoraciones del grupo, también las de asignaturas que quedan ocultas en ese grupo. Es un agregado de 5 o más personas; la supresión complementaria impide deducir la celda oculta restando (§5.2). El prototipo solo usaba las asignaturas visibles; las cifras difieren de 0,01 a 0,02 en algunos grupos.
- **Personal sin segmento:** la respuesta que no indica si es docente o su antigüedad se excluye de todos los resultados de personal, porque el total menos los segmentos la dejaría al descubierto. El informe de carga lo registra.
- **"n" en una asignatura o un grupo:** número de personas con al menos una valoración válida en ese conjunto. **"n" en una pregunta:** número de valoraciones válidas.
- **Recomendación:** media de la puntuación. **NPS** = % de puntuaciones de 9 y 10 menos % de puntuaciones de 6 o menos. Es el mismo umbral en las escalas de 0 a 10 y de 1 a 10.
- **Redondeo:** se calcula siempre con precisión completa y se redondea **solo al mostrar**: 2 decimales en medias de 1 a 6, 1 decimal en recomendación y entero en porcentajes y NPS, siempre alejándose del cero en el medio punto. Las RPC devuelven valores sin redondear.

---

## 4. Modelo de datos (propuesta)

- `curso` (id, nombre)
- `colectivo` (alumnos, familias, personal)
- `cuestionario` (id, curso, colectivo, codigo, titulo, respuestas_incompletas)
- `bloque` (id, cuestionario, nombre, entra_en_media)
- `pregunta` (id, codigo_diccionario, texto_es, tipo: escala, recomendacion o seleccion_multiple, **escala_min, escala_max**). **La escala vive en la pregunta.** Todas las preguntas de un bloque comparten escala; valídalo en la carga.
- `opcion` (id, pregunta, codigo, texto_es, texto_en): opciones de selección múltiple («Aspectos más destacados»), con su equivalencia en inglés
- `pregunta_cuestionario` (cuestionario, bloque, pregunta, orden, por_asignatura, por_departamento). Una pregunta no puede ser a la vez por asignatura y por departamento.
- `pregunta_comun` (codigo_comun, pregunta, colectivo): para el panel general (§7.1)
- `etapa` (Infantil, Primaria, PAI, Bachillerato)
- `grupo` (id, curso, etapa, nivel, nombre). **La etapa se obtiene siempre del grupo.**
- `asignatura` (id, curso, nombre normalizado)
- `departamento` (id, curso, nombre, oficial). Los oficiales del Colegio son nueve (Lengua y Literatura Españolas, Lengua y Literatura Inglesas, Adquisición de Lenguas, Matemáticas, Ciencias, Individuos y Sociedades, Artes Escénicas, Artes Visuales y Tecnología, Educación Física). «Otros» no es oficial ni tiene jefe: agrupa a quien no pertenece a ninguno.
- `departamento_equivalencia` (departamento de la encuesta, departamento oficial): los departamentos tal como aparecen en la matriz de reuniones de la encuesta de personal (filas de `departamento` con `oficial = false` cuando su nombre no es oficial) y a qué departamentos oficiales corresponden. Sin fila, un departamento de la encuesta equivale a sí mismo. En 2025/26, «Lengua Española y Literatura» corresponde a Lengua y Literatura Españolas, «Artes Visuales y Diseño» a Artes Visuales y Tecnología, e «Inglés y Adquisición de Lenguas» a dos oficiales: Lengua y Literatura Inglesas y Adquisición de Lenguas.
- `persona_responsable` (id, nombre, apellidos, correo, departamento nullable, situacion: alta o baja). Situación según Alexia; los dados de baja se incluyen y la vista lo indica.
- `cargo` (persona_responsable, curso, tipo: jefe_departamento, jefe_equipo o direccion, ambito). Para jefe_departamento, el ámbito es el departamento oficial (una persona puede tener varios). Para jefe_equipo, el tramo del Equipo de Individuación: infantil, y1_y5, y6_y9 o y10_y12. Se carga desde `datos_locales/responsables_2526.xlsx` (no va a git).
- `asignacion_docente` (curso, grupo, asignatura, docente). **Clave primaria de las cuatro columnas:** admite varios docentes por asignatura y grupo (codocencia, desdobles). Se genera desde el listado de Alexia (`etl/convertir_alexia_2526.py`). Una combinación grupo y asignatura con más de un docente es una **clase compartida** (§5.12).
- `privado.respuesta_docente` (respuesta, asignatura, docente): atribución de una respuesta de alumno a un docente concreto a partir del nombre que escribió o de la optativa (§7.2). Se guarda solo el docente resultante, nunca el texto.
- `privado.respuesta_tramo` (respuesta, tramo): tramo de tutoría (infantil, y1_y5, y6_y9, y10_y12), solo de quien contestó el bloque del Equipo de Individuación (§5.13).
- `respuesta` (id interno, cuestionario, grupo nullable, idioma_origen, docente, antiguedad, departamento_equipo). El grupo solo existe en el alumnado (y puede faltar). Los segmentos de personal son columnas tipadas; no hay jsonb ni sexo.
- `respuesta_etapa` (respuesta, etapa): **solo familias**, una fila por etapa marcada. En el alumnado la etapa se obtiene del grupo o del cuestionario.
- `respuesta_item` (respuesta, pregunta, asignatura nullable, departamento nullable, valor nullable, ns_nc). El departamento (de `departamento_encuesta`) solo aparece en el bloque "Reuniones de departamento" de personal.
- `respuesta_opcion` (respuesta, pregunta, opcion)
- `usuario_perfil` (auth user id, nombre, rol, etapa nullable, activo, ultimo_acceso)
- `registro_actividad` (usuario, accion, detalle, fecha). **Solo se escribe desde el servidor** (dentro de las RPC o por trigger), nunca con un insert del cliente.

Ninguna política RLS permite `select` desde el cliente sobre `respuesta`, `respuesta_item` ni `respuesta_opcion`.

---

## 5. Anonimato: mínimo de 5 y supresión complementaria

### 5.0 Criterio según el rol (confirmado por escrito por Mark el 28/10/2026)

- **Dirección y administración** ven todos los resultados, también los de menos de 5 respuestas, con la marca «menos de 5» y su número de respuestas. Para estos roles **no se aplica la supresión complementaria**. Vale en todas las vistas, informes, CSV y PDF que descargan.
- **La coordinación** y **el informe que recibe cada docente** (la «versión docente», también por su enlace personal, §7.10) siguen con el mínimo de 5 y la supresión complementaria: todo lo que sigue en este apartado.
- **Cómo se aplica:** en el servidor, en un solo sitio (`privado.ve_menos_de_5`, migración 20261028000030). `privado.suprimir` no suprime nada para Dirección y administración, y `privado.fila` marca `"menos_de_5": true` en cada resultado visible con menos de 5. La versión docente la pide `informe_profesor(..., p_version => 'docente')` y el enlace del docente; la coordinación la recibe siempre, pida lo que pida. El ajuste que la activa solo puede endurecer el criterio, nunca ablandarlo.
- **Presentación:** la cifra de respuestas lleva al lado «menos de 5» (en pantalla, como etiqueta; en CSV, «3 (menos de 5)»; en PDF, debajo de la cifra) y la nota «“menos de 5” junto a una cifra: resultado con menos de 5 respuestas, visible solo para Dirección y administración. Con tan pocas respuestas, cada persona pesa mucho en el resultado y es más fácil reconocerla».
- **Aspectos con mayor y menor valoración (§7.1):** para Dirección y administración entran también las preguntas con menos de 5 valoraciones, marcadas.
- **Informes de jefatura y de equipo (decisión del 28/10/2026):** dos versiones, como el del profesor/a. La **completa**, solo para Dirección y administración, con «no entregar a la jefatura»; la **versión para la jefatura**, con el mínimo de 5 y la complementaria (en el Equipo de Individuación, el tramo que queda oculto sale junto con los demás ocultos, como antes, §5.15). **Al enviarlos, siempre la versión para la jefatura** (§7.10). El informe de Dirección y el de todo el equipo solo los descargan Dirección y administración: salen con su criterio.
- Tests: `supabase/tests/25_criterio_direccion.sql`. Los tests anteriores de anonimato (02, 04, 06, 08, 09 y 10) siguen comprobando el mínimo y la complementaria en la versión docente.

1. **Mínimo:** ningún resultado agregado con n < 5. Se devuelve como suprimido, sin valor.
2. **Supresión complementaria:** cuando una vista enseña a la vez un total y sus partes (grupos de un cuestionario, asignaturas y grupos de un profesor/a, etapas, segmentos de personal), si **exactamente una** parte queda suprimida, se suprime también la siguiente parte más pequeña. Así no se puede deducir la parte oculta restando al total.
3. **Media global del profesor/a:** se calcula **solo con las combinaciones visibles**. El informe indica cuántas combinaciones se han excluido por tener menos de 5 respuestas.
4. **Filtros de personal:** un solo filtro a la vez (docente o no docente, antigüedad). No se combinan.
5. **Segmentos que siempre quedan ocultos** (familias de Bachillerato, con 3 respuestas): se muestran con un aviso explicando el motivo, no se omiten en silencio.
6. **Etapas solapadas (familias):** una familia cuenta en cada etapa que marcó y una sola vez en el total, así que las etapas no suman el total. La supresión complementaria se aplica igual entre etapas: si una sola etapa queda oculta, se oculta también la siguiente más pequeña.
   - **"Sin etapa":** las respuestas de familias sin ninguna etapa marcada forman una parte implícita "Sin etapa". Cuentan en el total, no se muestran como filtro ni como fila, pero participan en la supresión complementaria como una parte más: con menos de 5, cuenta como parte oculta; con 5 o más, como parte visible a efectos de la regla (y puede ser ella la que se oculte por complementaria), aunque siga sin mostrarse.
   - Ejemplo de 2025/26: "Sin etapa" (4) y Bachillerato (3) quedan ocultas; como ya hay dos partes ocultas, Infantil sigue visible. Si "Sin etapa" fuera 0, Bachillerato quedaría sola y se ocultaría Infantil, la siguiente más pequeña.
   - Como las etapas se solapan (familias con hijos en varias), la resta del total menos las partes visibles no da una cifra exacta de las ocultas. Aun así, la regla se aplica igual, por prudencia.
   - En la vista, junto al número de respuestas, una nota informa de las familias sin etapa con el mismo criterio que cualquier parte: "menos de 5" mientras sean menos de 5, la cifra exacta si su parte es visible y "5 o más" si se oculta por complementaria.
7. **Reuniones de departamento (personal):** el departamento es una dimensión del ítem. El bloque solo se consulta repartido por departamento, con el mínimo de 5 y la complementaria. Ninguna RPC lo cruza con otras respuestas de la misma persona: no admite filtros de segmento y el departamento no sirve para filtrar otros bloques ni para contar personas.
8. **Presentación de lo oculto:** "menos de 5" cuando la parte tiene menos de 5 respuestas; "oculto" cuando es por supresión complementaria, con aviso y leyenda "oculto para proteger el anonimato". En los PDF, nota al pie.
9. **Ámbitos de responsables** (departamento, equipo): mismas reglas. Con equipos de menos de 5 personas, el resultado se oculta y el informe lo dice. Cuando una jefatura tiene varios departamentos, cada uno se calcula por separado; si la encuesta junta dos departamentos oficiales en una sola unidad («Inglés y Adquisición de Lenguas» en 2025/26), el resultado es uno y el informe lo explica.
10. Todo lo anterior se aplica dentro de las RPC, y por tanto también en CSV y PDF.
11. **Idioma de origen (personal):** no es un filtro ni una dimensión. Los resultados de personal van siempre unidos y ninguna RPC devuelve resultados por idioma. El recuento de personas por idioma ("N en español · N en inglés") es solo informativo, se muestra con cifras exactas y queda fuera de la supresión, precisamente porque no existe ningún resultado desagregado por idioma que se pueda deducir por resta.

12. **Clases compartidas** (más de un docente en el mismo grupo y asignatura de la encuesta: codocencia, desdobles por niveles, Música y preguntas que agrupan varias materias):
   - en el informe del profesor/a van aparte, en «Valoraciones compartidas», con las mismas reglas de mínimo y complementaria;
   - la **media global del profesor/a se calcula solo con sus clases propias visibles** (las de un solo docente); las compartidas no entran;
   - en los resultados generales (Alumnado) siguen apareciendo como hasta ahora.
13. **Tramo de tutoría en el Equipo de Individuación** (autorizado el 21/10/2026, §7.3): solo existe como dimensión del bloque del Equipo de Individuación y de sus preguntas, sin otras dimensiones ni filtros. Ninguna otra métrica ni RPC lo admite (tests en `supabase/tests/09_jefes_tramos_atribucion.sql`). Complementaria entre los cuatro tramos.
15. **Partes de un mismo responsable juntas:** dos o más partes (tramos o departamentos) se muestran juntas solo si cada una está oculta por separado y juntas llegan a 5. Si una se ve y otra no, el conjunto se oculta, porque restando la visible se deduciría la oculta. Las RPC aceptan esos conjuntos solo internamente: el cliente no puede pedirlos.
14. **Atribución por nombre** (autorizada el 21/10/2026, §7.2): parte una clase compartida en un subconjunto por docente y uno «sin atribuir». La complementaria se aplica entre esos subconjuntos con el total de la clase visible, igual que entre los grupos de un cuestionario.

Tests obligatorios: una batería de casos en `supabase/tests` que intente saltar la regla por resta y por combinación de filtros.

---

## 6. Roles y permisos (Fase 1)

| | Administración | Dirección | Coordinación de etapa |
|---|---|---|---|
| Panel general | Todo | Todo | Solo alumnado y familias de su etapa; sin personal |
| Alumnado | Todo | Todo | Solo los cuestionarios de su etapa |
| Familias | Todo | Todo | Solo su etapa |
| Personal → Encuesta de personal | Sí | Sí | No |
| Personal → Informes por persona → Dirección, Equipos y Departamentos | Sí | Sí | No |
| Personal → Informes por persona → Profesorado | Sí | Sí | **Solo el profesorado con docencia en su etapa**, y solo con los resultados de esa etapa. Ve también la media del Colegio como referencia |
| Respuestas abiertas (§7.9) | Sí | Sí | **No** |
| Resultados de menos de 5 (§5.0) | Sí, marcados | Sí, marcados | No (mínimo de 5 y complementaria) |
| Informe del profesor/a | Completo y docente | Completo y docente | Solo el docente |
| Informes de jefatura y de equipo | Completo y para la jefatura | Completo y para la jefatura | No |
| Envío de informes al profesorado (§7.10) | Sí | No | No |
| Accesos y registro de actividad | Sí | No | No |

Correspondencia de cuestionarios con etapas:
- Primaria (Y2 a Y5) → Primaria.
- Los tres de PAI → PAI.
- Los dos de Bachillerato → Bachillerato.
- La coordinación de Infantil solo ve familias de Infantil, porque no hay encuesta del alumnado de Infantil.
- **Familias, referencia del Colegio (decisión del 26/10/2026):** la coordinación ve, junto a los de su etapa, los resultados de las familias de todo el Colegio (respuestas, valoración general, satisfacción media, recomendación y media de cada bloque), como referencia y sin poder repartirlos ni filtrarlos. Cuando su etapa no llega a 5, el mensaje lo dice con el curso y la etapa («En 2025/26 respondieron menos de 5 familias de Bachillerato…»), sin dar la cifra exacta (regla del mínimo de 5), y remite a la referencia. En Alumnado, al elegir un grupo oculto, el mensaje equivalente (menos de 5 o resta) y el total del cuestionario como referencia, que ya puede ver quien ve el grupo.

El profesorado y las jefaturas no tienen cuenta en la Fase 1: reciben su informe en PDF.

---

### Estado vacío (corrección del 26/10/2026)
«Todavía no hay resultados cargados» solo aparece cuando el servidor confirma que no hay encuestas del curso. Si deniega el acceso (sesión sin doble factor, acceso desactivado) la pantalla dice «No tienes acceso a estos datos», con un botón para volver a entrar; si falla la conexión, «No se han podido cargar los resultados». Un administrador sin el doble factor no pide ningún dato ni ve ninguna pantalla de resultados. Al abrir la web, la sesión guardada se valida con el servidor antes de pedir datos (y se renueva si se guardó con otra versión de la web); si el servidor no la reconoce, se vuelve a la pantalla de acceso.

### Identificadores de las respuestas (decisión del 26/10/2026)
Las respuestas y sus valoraciones tienen un identificador aleatorio, no correlativo, para que nadie con acceso a la base de datos pueda deducir el orden en que llegaron. Las de 2025/26 se renumeraron y reescribieron en orden aleatorio (migración 24).

## 7. Funcionalidades

### 7.0 Navegación
Menú: **Inicio (panel general) · Alumnado · Familias · Personal · Informes por persona**, y **Accesos** para administración (decisión del 22/10/2026: «Informes por persona» pasa de un apartado de Personal a una entrada propia del menú, para que se encuentre a la primera).

**Personal:** la encuesta de personal, lo que opina el personal como empleado. Filtros de uno en uno: todo el personal, docentes, no docentes, primer año, más de un año (§7.4). Arriba, un enlace corto a «Informes por persona» para quien los busque ahí. La coordinación no tiene esta entrada.

**Informes por persona**, de arriba abajo en la jerarquía del Colegio, cada nivel con su PDF:
- **Dirección:** Superiores (según el personal no docente) y la valoración del centro por todo el personal.
- **Equipos:** Equipo de Individuación (por jefatura de equipo si se aprueba el tramo de tutoría, §7.3; si no, un único informe del equipo).
- **Departamentos:** **por jefatura de departamento**, con cada uno de sus departamentos dentro: reuniones de departamento (con el mínimo de 5) y la media del profesorado del departamento según el alumnado (solo clases propias visibles, como la media global del profesor/a, §5.12).
- **Profesorado:** valoración de cada profesor/a por parte del alumnado (§7.2), con buscador y PDF individual y en lote.

La coordinación entra directamente en Profesorado (el de su etapa).

Direcciones: `#/personal` y `#/informes/<direccion|equipos|departamentos|profesores>`. Las antiguas llevan a su nuevo sitio: `#/personal/informes/<nivel>` a `#/informes/<nivel>`, `#/profesorado` a Profesorado y `#/responsables` a Dirección. La lógica está en `src/navegacion.ts`, con sus tests.

#### Navegar al detalle al pulsar (decisión de Mark, visto bueno de Rodrigo el 30/10/2026)
Al pulsar un elemento de un gráfico o de una tabla se entra en su detalle: se aplica un filtro en la misma pantalla o se abre otra pantalla o informe ya filtrado.

- **Tarjeta:** la de cada elemento con detalle acaba en «Pulsa para ver el detalle». Lo que no lleva a ningún sitio no cambia.
- **Teclado:** el elemento recibe el foco con Tab y se abre con Intro o la barra espaciadora. **Móvil:** la primera pulsación muestra la tarjeta con el enlace «Ver el detalle»; pulsar fuera la cierra.
- **Pantalla de destino:** arriba, la banda «Detalle» con el filtro aplicado, «Volver» (a la pantalla de la que se llegó) y «Quitar el filtro». Si el destino es un apartado (detalle por pregunta, un departamento, una clase), la página baja hasta él y lo resalta.
- **Filtros en la dirección de la página** (`#/familias?etapa=pai`): solo las claves que acepta cada pantalla (`PARAMETROS` en `src/navegacion.ts`), y `volver` con la dirección de origen. Una pantalla que el rol no puede ver no recibe filtros: la coordinación que escribe `#/personal?…` acaba en Profesorado sin ellos.
- **Reglas de cada rol:** el detalle sale de las mismas RPC, con el filtro aplicado, así que cada rol ve lo de siempre: Dirección y administración, también lo de menos de 5, marcado y con su número; la coordinación, con el mínimo de 5 y la complementaria. Para la coordinación, lo oculto no se puede pulsar y no hay destinos a pantallas que no tiene (Personal, Equipos, Departamentos, Respuestas abiertas). Lo impone el servidor; la web solo evita ofrecerlo (`src/detalle.ts`).
- **Exportación:** el CSV y el PDF de la pantalla de detalle llevan sus filtros en la cabecera y en el registro de descargas, como siempre. En Profesorado, el lote de PDF se limita a la lista filtrada.

Destinos:

| Pantalla | Elemento | Lleva a |
|---|---|---|
| Inicio | Recomendación: Primaria · PAI y Bachillerato · familias · personal | Alumnado (con el cuestionario de Primaria) · Alumnado · Familias · Personal |
| Inicio | Aspectos con mayor y menor valoración, preguntas comunes | La pantalla del colectivo, en el bloque de la pregunta y con ella resaltada (en alumnado, en su cuestionario) |
| Inicio | Más valorados (familias y personal) · recomendadores y no recomendadores | El apartado «Más valorados» · el bloque en el detalle por pregunta |
| Alumnado | Satisfacción general por grupo | La misma pantalla, filtrada por ese grupo |
| Alumnado | Profesorado por asignatura | Informes del profesorado, con la lista limitada a quienes dan esa asignatura en ese cuestionario y grupo (`profesores_de_clase`, migración 20261030000042) |
| Alumnado | Satisfacción por bloque · indicador de profesorado | El detalle por pregunta de ese bloque |
| Familias | Bloques · valoración general por etapa | El detalle por pregunta del bloque · la misma pantalla, filtrada por la etapa |
| Personal | Dimensiones · Superiores (docente o no docente) | El detalle por pregunta de la dimensión · la misma pantalla, filtrada por el segmento |
| Personal | Reuniones de departamento | El informe de jefatura de ese departamento, centrado en él (sin pantalla nueva). Un departamento sin jefatura no se puede pulsar |
| Personal | Equipo de Individuación | Informes del Equipo de Individuación |
| Informe de jefatura | Profesorado de sus departamentos según el alumnado | Informes del profesorado, con la lista limitada a esos departamentos |
| Informe del profesor/a (versión completa) | Cada clase | Su detalle pregunta por pregunta, desplegado. En la versión docente no se puede pulsar |

Tests: `supabase/tests/29_detalle_al_pulsar.sql` (cada destino con el criterio de cada rol) y `src/detalle.test.ts`.

### 7.1 Panel general (inicio tras el login)
1. **Recomendación del Colegio por colectivo:**
   - la comparación entre colectivos se hace con las barras de reparto (§7.8), no con el índice;
   - **el alumnado se muestra en dos barras**, Primaria por un lado y PAI y Bachillerato por otro, porque tienen escalas distintas;
   - el índice de recomendación y la media aparecen como datos secundarios, con una nota sobre las escalas.
2. **Preguntas comunes:** barras agrupadas con la media de 1 a 6 de cada colectivo en las preguntas compartidas. Candidatas, a confirmar con el Colegio y cargar en `pregunta_comun`:
   - En los tres colectivos: "El ambiente del Colegio es de respeto y convivencia".
   - Familias y personal: competencia profesional del profesorado; apoyo personal y académico del profesorado; atención a las necesidades individualizadas; valores éticos; el modelo educativo prepara para el futuro; mentalidad internacional; innovación; lectura; artes; música; competencias digitales; cultura; enseñanza de idiomas; Biblioteca; acceso a la primera opción de carrera; conciencia medioambiental.
   - Alumnado y familias: servicios (Comedor, Canasto, Biblioteca, Limpieza, Portería, Secretaría Académica, Servicio de Orientación y Transporte), y "Los recursos usados favorecen el aprendizaje".
3. **Aspectos más destacados por colectivo:** porcentaje de personas que eligen cada aspecto, comparado entre los tres colectivos.
   - **Aspectos menos destacados** (decisión del 22/10/2026; nombre de la revisión de lenguaje del 27/10/2026): los cinco aspectos con menor frecuencia de selección en cada colectivo, con la nota de que es una frecuencia de selección y no una valoración.
6. **Aspectos con mayor y menor valoración** (22/10/2026): por colectivo, las 5 preguntas de 1 a 6 con la media más alta («Mayor valoración», primero) y las 5 con la más baja («Menor valoración»), con el porcentaje que da de 1 a 3. Solo preguntas con 5 o más valoraciones; totales del colectivo, sin filtros (RPC `puntos_colectivo`).
7. **«Diferencias entre respuestas favorables y desfavorables a la recomendación»** (22/10/2026): media de cada bloque de 1 a 6 en las respuestas desfavorables (6 o menos) y en las favorables (9 y 10), ordenado por la diferencia. Es una comparación, no una causa, y la vista lo dice. Dimensión «recomienda» (no recomienda, recomienda y «resto»: 7 y 8 o sin respuesta), solo para la media de un bloque, sin combinarse con ningún otro filtro, con el mínimo de 5 y la complementaria entre los tres grupos. Solo administración y dirección (RPC `comparacion_recomendacion`). Sustituye al análisis opcional del punto 5.
4. **Indicadores por colectivo:** respuestas, satisfacción general, recomendación y NPS.
5. **Opcional, construir solo si Rodrigo lo confirma:** "qué pesa más en la recomendación", la correlación entre la media de cada bloque y la recomendación de cada persona, con un mínimo de 30 respuestas.

### 7.2 Vista e informe del profesor/a
- Buscador de docentes. Muestra los resultados de las encuestas del alumnado de sus asignaturas y grupos:
  - media por asignatura y grupo;
  - media global (§5.3), **solo con sus clases propias** (§5.12);
  - detalle por pregunta;
  - comparación con la media de su etapa y la del Colegio.
- **Dos secciones** (decisión del Colegio, 21/10/2026), en pantalla y en PDF:
  - **«Sus clases»:** grupos y asignaturas en los que es el único docente. De aquí sale la media global.
  - **«Valoraciones compartidas»:** clases con más de un docente (codocencia, desdobles por niveles, Música y preguntas que agrupan varias materias), con una nota: «El alumnado valora la asignatura, no a cada docente. Estas valoraciones son compartidas con otros docentes y no entran en su media».
- **Docentes de baja:** se incluyen, porque dieron clase ese curso.
- **Inmersión lingüística** (Y6 a Y10): no se atribuye; sus grupos no son grupos de clase.
- **Optativa** (Y6 a Y9): se atribuye por el nombre de la optativa cuando esta tiene un solo docente. Como las optativas mezclan grupos, el resultado del docente es de todos sus grupos juntos, con la complementaria entre docentes dentro de la asignatura.
- **Dos versiones del informe** (confirmado por Mark el 28/10/2026, §5.0):
  - **Completa**, para Dirección y administración: además de la media global y la de cada clase, el **detalle de cada pregunta en cada clase** (asignatura y grupo), con la marca «menos de 5» donde corresponda. La media global incluye todas sus clases propias; el informe dice cuántas tienen menos de 5 y cuál es la media de la versión docente.
  - **Docente**, la que recibe el docente: igual que hasta ahora (mínimo de 5 y complementaria, media global solo con las clases visibles).
  - El PDF lo dice en la cabecera («Versión completa» o «Versión docente») y bajo el nombre («Versión completa (Dirección y administración) · no entregar al docente»). Archivo: `Informe_2526_Apellido_Nombre_completo.pdf` y, la docente, `Informe_2526_Apellido_Nombre.pdf`. En lote se elige la versión. El registro de actividad y el de descargas anotan la versión.
- **PDF por profesor/a:** descarga individual y en lote (ZIP, `Informe_2526_Apellido_Nombre.pdf`), con el estilo del Colegio. La generación queda en el registro de actividad.
- **Origen:** el listado de Alexia del Colegio (grupos, asignaturas y docentes), convertido con `etl/convertir_alexia_2526.py` al formato de la plantilla (`etl/plantillas/asignacion_docente_2526.xlsx`) y cargado con `etl/cargar_asignaciones.py`. Las materias de Alexia se casan con las de la encuesta mediante una tabla de equivalencias por cuestionario. Las que los alumnos no valoran (tutoría, refuerzos, CICE y similares) no se cargan.
- **Departamento:** el que confirmó el Colegio en la revisión (la columna «Departamento correcto» manda; «Sin dpto.» es «Otros»), con los nombres oficiales. El antiguo «Inglés y Adquisición de Lenguas» se reparte entre Lengua y Literatura Inglesas y Adquisición de Lenguas según lo que imparte cada docente; quien dé de las dos se marca para revisión.
- **Atribución por el nombre que escribió el alumno** (decisiones del 21 y 22/10/2026): solo en las columnas en las que el nombre casa con un único docente en el 90 % o más (`etl/atribucion_2526.py`).
  - Por las bajas, el alumnado nombra al profesor/a que más tiempo le ha dado clase, que no siempre es el titular de Alexia. **La valoración va al informe del profesor/a nombrado.** El nombre se busca entre los docentes de esa asignatura en el grupo, después entre los del grupo y por último en todo el Colegio.
  - Se atribuye en las clases con varios docentes y cuando el alumno nombra a alguien que no es el titular. En una clase con atribución, cada docente nombrado recibe su subconjunto; un titular al que no nombró nadie no recibe nada de esa clase.
  - Los docentes que no están en Alexia se añaden en `datos_locales/docentes_adicionales_2526.xlsx` (nombre, correo y departamento).
  - Inglés de Y12: atribuido (todos los nombres casan, la mayoría con un sustituto). Inglés de Y10: las 16 respuestas del alumnado de Y10 D nombran a una persona que no está en Alexia; hasta añadirla, la columna casa en el 72 % y la clase sigue como valoración compartida. El texto nunca se carga: solo la atribución. El informe de la carga recoge, en cifras, cuántas respuestas del alumnado rellenaron cada columna, cuántos casan y cuántas respuestas se atribuyen. Análisis del 21/10/2026 (cifras agregadas; el texto libre no se carga):
  - Solo hay columnas de nombre en Y10 (Lengua Española, Inglés y Francés), Y11 (Inglés, Historia, Matemáticas y Química) y Y12 (Inglés, Matemáticas, Química y Biología). En Primaria solo se pregunta por el profesor/a de instrumento (Música PIM, que no se atribuye) y en Y6 a Y10 no hay ninguna.
  - La rellenan entre el 84 % y el 92 % del alumnado en las asignaturas comunes, el 70 % en Francés y entre el 36 % y el 44 % en Química y Biología (optativas: no las cursan todos).
  - El nombre casa con un único docente de Alexia de esa asignatura y ese grupo en el 98 % al 100 % de los casos, salvo Inglés de Y10 (34 %) y de Y12 (38 %). Ahí el alumnado nombra a docentes que Alexia no pone en ese grupo o en esa asignatura, lo que apunta a un hueco en el listado de Alexia.
  - Solo cambia algo en las clases con varios docentes: 24 subconjuntos por docente, de los que 21 llegarían a 5 o más respuestas del alumnado.
  - La encuesta de Y6 a Y9 pregunta además el nombre de la optativa: la rellena el 98 % y casa con una optativa del listado de Alexia en todos los casos. 11 de las 13 optativas tienen un solo docente, así que la pregunta «Optativa» podría atribuirse.

### 7.3 Informes de responsables (Personal → Informes por persona: Dirección, Equipos y Departamentos)
- **Nombres oficiales** (21/10/2026): departamentos como en §4 y «Equipo de Individuación» (antes «Individualización» en la interfaz). Jefaturas de departamento y de equipo en `datos_locales/responsables_2526.xlsx`.
- **Informe de departamento por jefatura:** un PDF por persona con cada uno de sus departamentos dentro. La media del profesorado según el alumnado es **una sola por jefatura** (decisión del 22/10/2026: Inglés y Adquisición de Lenguas son un único departamento, igual que Artes Visuales y Tecnología con Educación Física): la media agrupada de todas las clases propias y atribuidas visibles de los docentes de sus departamentos, sin desglose por departamento oficial. En la base siguen los 9 cargos, uno por departamento oficial. Si los departamentos de una jefatura no tienen ninguna clase propia (todas compartidas, como Música en Artes Escénicas), no se muestra «oculto», porque no es una supresión por anonimato, sino el aviso «Sin media de departamento: todas las clases de sus departamentos son compartidas entre varios docentes. Las valoraciones de cada docente aparecen en su informe, en “Valoraciones compartidas”». Dos jefes tienen dos departamentos:
  - uno tiene Lengua y Literatura Inglesas y Adquisición de Lenguas, que funcionan unidos (todos sus docentes responden a esa jefatura) y en la encuesta de 2025/26 son una sola unidad: una sección de reuniones con nota, y la media de alumnos por cada departamento;
  - otro tiene Artes Visuales y Tecnología (4 personas en la matriz) y Educación Física (2): por separado los dos quedan ocultos y se muestran juntos como «sus departamentos», con una nota (decisión del 21/10/2026, §5.15).
- **Equipo de Individuación por jefatura** (análisis del 21/10/2026, con recuentos): de los 18 profesorado tutor que contestaron el bloque, por el nivel de tutoría que marcaron, Y6 a Y9 son 7, Y10 a Y12 son 5, Y1 a Y5 son 4 e Infantil 2. Con el mínimo de 5 y la complementaria:
  - la jefatura de Y6 a Y9 tendría resultado en las 22 preguntas;
  - el de Y10 a Y12 en 20 de 22 (en dos preguntas contestaron 4);
  - Y1 a Y5 e Infantil quedan ocultos. Juntos suman 6 y su resultado se deduce del total menos los otros dos, así que se puede mostrar como «Infantil y Y1 a Y5», compartido por sus dos responsables.
  - **Autorizado el 21/10/2026:** se carga el nivel de tutoría solo como tramo (cuatro valores) y solo para este bloque (§5.13). Resultados: Y6 a Y9, Y10 a Y12, e «Infantil y Y1 a Y5» compartido por sus dos responsables, con una nota. La lista de grupos se calcula con los datos: cada tramo visible va solo y los ocultos se juntan (§5.15). Se mantiene también el informe de todo el equipo.
- El personal valora a su jefatura en el bloque **"Superiores"** (7 preguntas: trato, dirección del equipo, trabajo en equipo, escucha, reconocimiento, comunicación descendente y comunicación ascendente).
- **Primer paso, bloqueante:** comprobar si el fichero de personal 2025/26 trae el departamento o el equipo de cada persona.
  - **Si lo trae:**
    - vista e informe PDF por responsable (individual y en lote) con el bloque Superiores de su ámbito;
    - los jefaturas de departamento ven además la media del profesorado de su departamento en las encuestas del alumnado, gracias a la columna de departamento del Excel.
  - **Si no lo trae:**
    - para 2025/26 se muestra el bloque Superiores agregado (todo el personal, y por docente y no docente);
    - el modelo queda preparado para 2026/27, cuando la Fase 2 preguntará el departamento o equipo;
    - el informe explica la limitación.
- **En 2025/26 el bloque Superiores solo lo contestó el personal no docente.** Los docentes valoran a su jefatura en las reuniones de departamento (jefatura de departamento) y en el bloque del Equipo de Individuación (jefatura de equipo). La vista lo explica y no muestra un reparto por docentes que estaría vacío.
- **Resultado de la comprobación (13/10/2026): el fichero de 2025/26 no lo trae.** Se aplica el plan alternativo: Superiores agregado y `departamento_equipo` vacío. No se deduce la pertenencia a un departamento a partir de qué columnas rellenó cada persona.
- **Bloques que sí existen en 2025/26:**
  - **Reuniones de departamento:** 21 afirmaciones sobre las reuniones de cada departamento y sobre su jefatura (trato, dirección, trabajo en equipo, reconocimiento, comunicación), contestadas solo por sus miembros. Hay 8 departamentos en la encuesta, que se cuadran con los oficiales mediante `departamento_encuesta_oficial` (§4). Con 5 o más personas: Lengua, Inglés y Adquisición, Ciencias y Matemáticas; Artes Escénicas no tiene datos válidos por un fallo del formulario. Se carga con el departamento como dimensión del ítem y solo se expone agregada por departamento (§5.7), en el informe del jefatura de departamento y en la vista de personal.
  - **Equipo de Individuación:** 22 afirmaciones que contestan los profesorado tutor sobre sus reuniones y sobre su jefatura de equipo (trato, dirección, trabajo en equipo, reconocimiento, comunicación). Va en el informe de ese jefatura de equipo.
- **Dirección:** su informe incluye el bloque Superiores del conjunto y la valoración del centro por parte del personal.
- **Dos versiones de los informes de jefatura** (de departamento y del Equipo de Individuación, decisión del 28/10/2026, §5.0): «PDF completo» (Dirección y administración, «no entregar a la jefatura») y «PDF versión para la jefatura» (mínimo de 5 y complementaria). La cabecera y el texto bajo el nombre dicen la versión; el archivo de la completa acaba en `_completo`. El registro anota la versión.

### 7.4 Vistas por colectivo
Se porta el prototipo `datos_locales/Tablero_Encuestas_2526_CIS-SFP.html`, que funciona con datos reales y ya tiene el estilo de la intranet. Se respetan las reglas nuevas: supresión complementaria, sin sexo y un filtro a la vez en personal.

- **Alumnado:**
  - filtros de cuestionario y grupo, e indicadores;
  - satisfacción general por grupo (30/10/2026; pulsar un grupo lo filtra);
  - detalle por pregunta de cada bloque (30/10/2026), con las etiquetas de la escala de cada bloque tal como vienen en sus encuestas (`src/escalas.ts`): frecuencia en profesorado, satisfacción en servicios, acuerdo en el resto, y las de Primaria;
  - profesorado por asignatura, tabla de colores de asignatura por grupo y satisfacción por bloque;
  - detalle por pregunta, aspectos con mayor y menor valoración;
  - recomendación y aspectos más destacados.
- **Familias:**
  - filtro por etapa, con aviso en Bachillerato;
  - valoración general del centro destacada, también comparada por etapa;
  - bloques, detalle, recomendación y NPS, y aspectos más destacados.
- **Personal:**
  - filtro de **docente o no docente** y filtro de antigüedad, nunca combinados;
  - indicadores y eNPS;
  - dimensiones, detalle, recomendación y aspectos más destacados;
  - en pequeño junto a las respuestas, el número de personas por idioma, como dato informativo y con cifras exactas (§5.11). Mientras no esté cargado el cuestionario en inglés: "Cuestionario en inglés pendiente de cargar"; después, "N en español · N en inglés". Los resultados van siempre unidos: las preguntas en inglés se mapean al mismo diccionario.

### 7.5 Accesos y administración
Funciones del mockup `referencia/mockups/Mockup_Encuestas_5_admin_usuarios.png`; el estilo es el de la intranet.
- Alta por invitación con nombre, correo, rol y etapa. Los accesos iniciales están en `datos_locales/responsables_2526.xlsx` y se invitan en el despliegue, no en local.
- **Inicio de sesión con Microsoft (futuro, no en la Fase 1):** el Colegio propone entrar con su cuenta de Microsoft (Entra ID) desde la intranet. Para no cerrarlo, toda la autenticación del frontend vive en `src/data/sesion.ts`, los perfiles se enlazan por el identificador de usuario de Supabase Auth y el correo, y los permisos no dependen de cómo se entra. Añadirlo será activar el proveedor de Microsoft en Supabase Auth y un botón en la pantalla de acceso, manteniendo la invitación previa.
- **Caducidad del enlace:** Supabase limita la validez de los enlaces de correo (como máximo 24 horas, compruébalo en la versión actual). Se usa el máximo permitido y el botón "Reenviar invitación". El texto de la interfaz dirá la caducidad real, no 72 horas.
- Desactivar, reactivar y reenviar invitación. Último acceso y aviso a los 90 días sin entrar.
- Eliminar (26/10/2026): borra la cuenta, el perfil, el doble factor, las sesiones y la invitación pendiente; se confirma escribiendo el correo de la cuenta. El registro de actividad conserva sus acciones pasadas con el nombre y el correo que tenía y anota quién lo eliminó. Solo administración; nadie se elimina a sí mismo ni al último administrador activo. Para dejar de entrar durante un tiempo, «Desactivar».
- Registro de actividad, escrito por el servidor: invitaciones, cambios de rol, desactivaciones, eliminaciones e informes consultados. Las descargas tienen su propia pestaña (§7.7).
- Doble factor (TOTP) obligatorio para las cuentas de administración. Solo en la base de datos local de desarrollo puede desactivarse (`app.mfa_admin_obligatorio = 'off'`, ver README); en producción no existe ese ajuste.
- Un acceso desactivado puede autenticarse, pero no obtiene ningún resultado (todas las RPC lo rechazan) y la aplicación le muestra que no tiene acceso.
- Reglas: una cuenta de administración no puede desactivarse ni quitarse el rol a sí misma, y siempre queda al menos una cuenta de administración activa.

### 7.8 Presentación de la recomendación (las tres encuestas, en pantalla y en PDF)
- **Dato principal:** el reparto en porcentajes, como barra de tres colores con el texto «X % respuestas favorables (9 y 10) · X % respuestas neutras (7 y 8) · X % respuestas desfavorables (6 o menos)».
- **Dato secundario:** «Índice de recomendación», con la explicación «Porcentaje de respuestas favorables menos porcentaje de respuestas desfavorables. Va de −100 a +100; por encima de 0 hay más respuestas favorables que desfavorables.»
- **Sin siglas en la interfaz:** NPS y eNPS no aparecen; solo en «Cómo se calcula»: «Índice de recomendación (conocido como NPS)».
- Es solo presentación: las RPC y los cálculos (§3) no cambian.

### 7.6 Exportación
- CSV por vista, generado por las RPC y sujeto a todas las reglas del §5.
- PDF de cada vista.
- Nunca se exportan respuestas individuales.
- Vistas con exportación: Panel general, Alumnado, Familias y Personal (Profesorado e Informes por persona tienen sus propios PDF). Se exporta lo que se ve con los filtros activos; en Familias y Personal, el detalle por pregunta de todos los bloques.
- CSV para Excel en español: UTF-8 con BOM, separador punto y coma, coma decimal y sin separador de miles.
- Celdas ocultas con el mismo texto que en pantalla («menos de 5», «oculto», «sin datos»); nunca en blanco. Para Dirección y administración, la cifra de respuestas de un resultado con menos de 5 lleva la marca: «3 (menos de 5)» (§5.0).
- Cabecera en el CSV y en el PDF: quién lo descargó, fecha y hora de la descarga y su código (§7.7), Colegio, curso, vista, filtros activos y «Resultados en validación» mientras esté activa la franja. El CSV empieza por «Confidencial · Uso exclusivo del Colegio».
- Nombre de archivo: `Encuestas_2526_<Vista>[_<Filtro>].csv` o `.pdf` (por ejemplo, `Encuestas_2526_Familias_Etapa-PAI.csv`).
- Cada exportación queda en el registro de descargas (§7.7), escrito por el servidor (`registrar_descarga`), con la vista, el formato, los filtros y su código. La coordinación no puede exportar personal.

### 7.7 Protección de PDF y CSV y registro de descargas (decisión del 27/10/2026)
- **Marca de agua** en todas las páginas de todos los PDF (informes por persona, vistas y panel): «CONFIDENCIAL · Uso exclusivo del Colegio Internacional de Sevilla, San Francisco de Paula», en diagonal y gris muy claro, detrás del contenido para no tapar cifras ni gráficos.
- **Pie de cada página:** «Descargado por [nombre] el [fecha] a las [hora] · Código [código]» y la página. Nombre, hora y código los pone el servidor al anotar la descarga. En un ZIP, cada PDF lleva su propio código y el ZIP el suyo.
- **Propiedades del PDF:** título, autor «Colegio Internacional de Sevilla, San Francisco de Paula», asunto «Confidencial» y permisos que impiden copiar el texto, editar, anotar y reorganizar páginas (se abre sin contraseña y se puede imprimir). Se cifra con AES-256 y una contraseña de propietario aleatoria que no se guarda (`src/pdf/proteger.ts`, con `@cantoo/pdf-lib`). Es una restricción del formato: la respetan los lectores habituales, pero no impide una captura de pantalla; la protección de verdad es la marca de agua y el código.
- **CSV:** primera línea «Confidencial · Uso exclusivo del Colegio» y, en la cabecera, quién lo descargó, cuándo y el código.
- **Código:** 8 caracteres sin los que se confunden (0/O, 1/I/L), en dos grupos («7KQ2-M9XD»), único en todo el registro.
- **Registro de descargas** (`registrar_descarga`, migración 20261027000029): una entrada del registro de actividad por descarga, con fecha y hora, persona, tipo (informe de profesor/a, de jefatura, de equipo, de dirección, vista en PDF, CSV o ZIP), de quién o de qué vista es, filtros, archivo y código; en un ZIP, la lista de informes con el código de cada uno. Primero se piden los datos (con los permisos de siempre), después se anota y por último se crea el archivo: si la anotación falla, no hay descarga.
- **Pestaña «Descargas» en Accesos** (`#/usuarios/descargas`, `admin_descargas`): filtros por persona, tipo, fechas y persona del informe (también dentro de un ZIP) y búsqueda por código (también el de cada informe de un ZIP); exportación a CSV de lo filtrado, con la misma cabecera, que también queda anotada. Solo administración. La actividad de la otra pestaña deja fuera las descargas.
- **Inalterable:** nadie desde la aplicación escribe en el registro, y un trigger impide cambiar o borrar una descarga a cualquier rol de la base de datos. Solo se permite lo que ya hacía eliminar una cuenta (guardar su nombre y correo).
- **Conservación (aprobada el 28/10/2026, para el encargo de tratamiento):** dos años desde cada descarga y, después, borrado. Cubre dos campañas, por si un documento aparece fuera del Colegio meses después. El borrado periódico está por construir: hoy el registro no deja borrar nada.
- Tests: `supabase/tests/23_registro_descargas.sql`, `src/pdf/proteger.test.ts` y `src/exportacion/csv.test.ts`.

### 7.9 Respuestas abiertas (confirmado por Mark el 28/10/2026)
- Se cargan **tal cual**, sin ocultar nada, desde los ficheros de 2025/26 (`etl/cargar_abiertas_2526.py`, después de `cargar_2526.py`). Son 18 preguntas y 750 respuestas: «¿Qué echas en falta en el Colegio?» y «Comentarios» en cada cuestionario del alumnado (la de Y12 solo tiene comentarios), en familias y en personal, y las tres del Plan de Igualdad en personal.
- **No se cargan** las columnas que piden el nombre de un docente o de la optativa (solo sirven para atribuir valoraciones, §7.2).
- **Solo Dirección y administración.** Nunca la coordinación ni los informes del profesorado. Entrada propia del menú: «Respuestas abiertas» (`#/abiertas`).
- **Pantalla por colectivo y pregunta**, con los filtros del colectivo: alumnado (etapa, cuestionario y grupo), familias (etapa) y personal (docente o no docente, o antigüedad, de uno en uno).
- **Sin vínculo con las respuestas cerradas:** cada respuesta abierta va suelta (`privado.respuesta_abierta`, sin `respuesta_id`), con identificador aleatorio y cargada en orden aleatorio, con solo lo necesario para los filtros. La RPC devuelve solo los textos.
- **Registro:** cada consulta queda en el registro de actividad (colectivo, pregunta, filtros y número de respuestas; nunca el texto). La exportación (CSV y PDF) lleva la marca de confidencialidad, su código y queda en el registro de descargas.
- **Plan de Igualdad (decisión de Mark del 30/10/2026):** sus tres preguntas abiertas (20 respuestas) se cargan como las demás, visibles **solo para Dirección y administración**, con el mismo registro. Del 28/10 al 30/10 estuvieron sin cargar, a la espera de esa decisión.
- **Preguntas de familias (textos oficiales, confirmados por Mark el 30/10/2026):** «¿Qué es lo que echa en falta en el Colegio?» y «Si desea añadir algún comentario, hágalo aquí por favor». La exportación de Encuesta Fácil no los trae (la cabecera es la del bloque): la carga reconoce cada pregunta por su posición y le pone su texto oficial. En la pantalla, familias muestra ese texto; alumnado y personal, el nombre común de la pregunta.
- **Conservación (28/10/2026, para el encargo de tratamiento):** el mismo plazo que el resto de respuestas. Propuesta, pendiente de confirmar por el Colegio: **5 cursos y después se borran**.
- RPC: `abiertas_preguntas`, `abiertas`, `abiertas_grupos` (migración 20261028000031). Tests: `supabase/tests/26_respuestas_abiertas.sql`.

### 7.10 Envío de informes al profesorado y a las jefaturas (confirmado por Mark el 28/10/2026)
- **Enlace personal por docente** a la versión docente de su informe, **válido 7 días**. Se abre sin cuenta (`#/informe/<token>`): enseña el informe y deja descargar el PDF, a nombre del docente y con su código. **Cada apertura y cada descarga quedan registradas.** El token solo existe en claro hasta que sale el correo; en la base de datos queda su huella (SHA-256). Un enlace se puede anular.
- **Jefaturas (decisión del 28/10/2026):** cada jefatura recibe su enlace a la **versión para la jefatura**, siempre: la de departamento, con todos sus departamentos, y la del Equipo de Individuación, con su tramo (o con los tramos que salen juntos). Se eligen en «Informes de jefatura», una a una o todas. Una persona que es docente y jefatura recibe un enlace por informe.
- **Envío individual o por departamento, etapa o tramo** (Y1 a Y5, Y6 a Y9, Y10 a Y12), o a todo el profesorado, siempre con **vista previa de destinatarios** antes de enviar y una confirmación. Quien no tiene resultados del alumnado o no tiene correo se queda fuera y la vista previa lo dice. Solo administración, en «Informes por persona › Envío al profesorado».
- **Remitente `encuestas@sfpaula.com`.** Mientras no exista, el envío está en **modo de pruebas**: solo a correos de Niage (@niage.es o @niage.eu), con «[PRUEBA]» en el asunto y el docente al que iría; **no se envía nada al profesorado**. Doble cerrojo: la base de datos (`privado.configuracion_envio.modo = 'pruebas'`) no crea enlaces a otros correos, y la Edge Function `enviar-informes` exige además `ENVIO_PROFESORADO=activo` y el remitente del Colegio. Pasar a «activo» lo hace Niage en la base de datos cuando el Colegio lo autorice; no hay botón.
- **Seguridad del enlace sin sesión** (tests en `supabase/tests/28_enlace_sin_sesion.sql`):
  - caducado o anulado no abre nada ni descarga el PDF, y no cuenta como apertura;
  - las funciones del enlace solo reciben el token: no se puede pedir el informe de otra persona, y abrirlo no deja ningún permiso abierto para otras funciones (resultados, otros informes, respuestas abiertas, registros, tablas);
  - un token alterado (una letra, recortado, alargado, en mayúsculas), inventado, vacío o la propia huella guardada no da acceso;
  - **límite de intentos (decisión del 29/10/2026):** 300 intentos fallidos en un minuto, en todo el servidor, cortan durante ese minuto la apertura de cualquier enlace (también los buenos), y queda una alerta en el registro de actividad para administración. Uno más bajo dejaría bloquear los enlaces del profesorado con muy poco esfuerzo. Los intentos se anotan sin IP ni token, solo con la hora y el motivo, y se borran al día. El límite se cambia en `privado.configuracion_envio.intentos_por_minuto`. Con tokens de 256 bits, adivinar uno ya es imposible; el límite es una defensa más y, como mucho, retrasa un minuto a quien abre su enlace en ese momento.
- Seguimiento: «Enlaces enviados», con la fecha de envío, la caducidad, las aperturas y las descargas de cada enlace.
- **Conservación (28/10/2026, para el encargo de tratamiento):** los envíos, los enlaces y sus aperturas, **dos años**, como el registro de descargas, y después borrado. El borrado periódico está por construir, junto con el de las descargas.
- RPC y tablas: migración 20261028000032. Tests: `supabase/tests/27_envio_informes.sql`.

---

## 8. Estilo: intranet CIS-SFP

Referencia: `referencia/plantilla-intranet-cis-sfp.html`. Ábrela en el navegador y lee sus páginas "Componentes" y "Guía técnica".

- Copia tal cual el bloque A (fuente Raleway embebida) y el bloque B. Los estilos propios van en un bloque C con el prefijo `en-`. No se incluye el bloque D.
- **Estructura de página:** skip link, `header.topbar`, `main#app`, `footer.footer`, `#toast`.
- **Orden dentro de cada página:**
  1. migas;
  2. `eyebrow`;
  3. `h1` con emoji;
  4. `lead`;
  5. secciones (`h2.section-title` + `.sec-lead`);
  6. `.notice`.
- **Componentes:** `.card`, `.btn`, `.btn.primary`, `.chips`, `.chip.on`, `.notice`, `.tbl-wrap` con `table.doc-table` y `.tiles`.
- **Paleta de gráficos, indicadores y alertas** (decisión del 26/10/2026; el resto del estilo sigue siendo el de la intranet). Se define en un único sitio, `src/paleta.ts`: la web la recibe como variables `--en-*` en `:root` y los PDF la importan de ahí.
  - Gráficos (series y categorías), en este orden: azul petróleo `#376878` (principal), verde salvia `#8DA9A5`, lavanda grisáceo `#9997B8` y azul acero `#597D9A`. Medias y barras simples, en petróleo. Comparaciones entre colectivos o series: los cuatro colores en ese orden (alumnos, familias, personal; «no recomendarían» y «recomendarían»).
  - Indicadores: positivo `#397F78`, negativo `#B66579`, neutro `#71869A`.
  - Escalas: de 1 a 6, el 1, 2 y 3 en tonos de negativo (más intenso en el 1) y el 4, 5 y 6 en tonos de positivo (más intenso en el 6); NS/NC en gris. Las demás escalas, en proporción (con número impar de valores, el central en neutro). La barra divergente va del 1 (a la izquierda) al 6 (a la derecha).
  - Recomendación: desfavorables en negativo, neutras en neutro y favorables en positivo.
  - Contraste: solo petróleo y positivo se usan como color de texto sobre blanco. Las alertas llevan el color en el borde, el icono o un fondo suave, con el texto en oscuro (`.notice.en-alerta`: neutro para avisos, `en-alerta-neg` para errores, `en-alerta-pos` para confirmaciones). Sobre cada tono, el texto es blanco u oscuro según el contraste. Salvia y lavanda nunca van como único elemento sin etiqueta.
  - Cifras o etiquetas visibles en todos los gráficos, para no depender solo del color: medias en las barras, porcentajes dentro de los tramos que caben, número de respuestas sobre las columnas y leyendas.
- **Responsive:** móvil, iPad y escritorio, con los puntos de corte de la plantilla (1260, 900, 620 y 600 px).
- **Accesibilidad:** botones y enlaces reales, foco visible, `alt` en las imágenes y etiquetas visibles en los formularios.
- **PDF:** mismo estilo (logo del Colegio, colores y tipografía) y generación en lote. La librería es libre.

---

## 9. Plan de trabajo

1. Repositorio y `.gitignore` (como mínimo `datos_locales/`, `.env*` salvo `.env.example`, `node_modules/` y `dist/`). README y estructura del proyecto. `docs/PROGRESO.md`.
2. Supabase (Irlanda, UE): migraciones, RLS, RPC con el §5 y tests de anonimato.
3. ETL de los seis cuestionarios del alumnado, el de familias y el de personal (español e inglés unidos). Diccionario y validación contra `datos_locales/validacion_2526.md`. **No se avanza hasta que cuadre.** En este paso se verifica también si personal trae departamento o equipo (§7.3).
4. Auth, perfiles, roles, invitaciones y doble factor de administración.
5. Diseño de la intranet y vistas por colectivo (portando el prototipo).
6. Panel general.
7. Vista e informes del profesor/a: primero con datos de ejemplo y después con el Excel.
8. Vista e informes de responsables, según el resultado del paso 3.
9. Administración de accesos y registro de actividad.
10. Despliegue, dominio, pruebas en móvil e iPad, manual de administración y guía de uso.

Commits pequeños. Al cerrar cada paso, actualiza `docs/PROGRESO.md`.

---

## 10. Pendientes y preguntas abiertas

| # | Tema | Quién | ¿Bloquea? |
|---|---|---|---|
| 1 | Descargar las exportaciones 2025/26 de SharePoint a `datos_locales/fuentes/` | Rodrigo | Paso 3 |
| 2 | ~~Excel de asignación docente por asignatura y grupo~~ Recibido (listado de Alexia y revisión de departamentos, 21/10/2026). Falta revisar los docentes que dan Inglés y Adquisición a la vez | Colegio | No |
| 3 | ~~Lista de jefaturas y su ámbito~~ Recibida (21/10/2026). El fichero de personal no trae departamento | Colegio | No |
| 4 | ¿Acepta el Colegio Supabase o pone su backend? | Rodrigo con sistemas | No (lógica aislada en `src/data/`) |
| 5 | Lista definitiva de preguntas comunes | Colegio | No |
| 6 | Escala de la satisfacción general del alumnado | Colegio | No |
| 7 | ¿Los PDF los envía el Colegio o la plataforma por correo? Por defecto, solo descarga | Rodrigo | No |
| 8 | Idiomas: ¿entra el inglés en la Fase 1? | Rodrigo | No |
| 9 | Registros DNS para el dominio y el remitente | Sistemas del Colegio | Paso 10 |
| 10 | ¿Construir el análisis de "qué pesa más en la recomendación"? | Rodrigo | No |
| 11 | ~~Atribución por nombre y optativa~~ Autorizada (21/10/2026), salvo Inglés de Y10 y Y12 | Colegio | No |
| 12 | ~~Equipo de Individuación por jefatura~~ Autorizado (21/10/2026) | Colegio | No |
| 13 | ~~Departamentos de una misma jefatura juntos~~ Autorizado (21/10/2026) | Colegio | No |
| 14 | ~~Inglés de Y10 y Y12~~ Son sustituciones por bajas: la valoración va al profesor/a nombrado (22/10/2026). Falta el nombre y el correo del docente de Inglés de Y10 D, que no está en Alexia | Colegio | No |
| 15 | ~~Departamento de 9 docentes de Inglés y Adquisición~~ No hace falta: los dos departamentos van unidos y responden a la misma jefatura (22/10/2026) | Colegio | No |

---

## 11. Material de la carpeta

| Ruta | Qué es | ¿Va a git? |
|---|---|---|
| `CLAUDE.md` | Reglas, arquitectura y estado | Sí |
| `docs/ESPECIFICACION.md` | Este documento | Sí |
| `referencia/plantilla-intranet-cis-sfp.html` | Plantilla oficial de la intranet: estilos, componentes y guía técnica | Sí |
| `referencia/mockups/` | Mockups 1 a 5 (Fase 1) y 6 (Fase 2), con datos de ejemplo. Sirven para la distribución y las funciones; el estilo es el de la intranet | Sí |
| `datos_locales/validacion_2526.md` | Valores de control de la carga | No |
| `datos_locales/referencia_agregados_2526.json` | Agregados verificados completos | No |
| `datos_locales/Tablero_Encuestas_2526_CIS-SFP.html` | Prototipo funcional con datos reales | No |
| `datos_locales/fuentes/` | Exportaciones originales de Encuesta Fácil | No |
