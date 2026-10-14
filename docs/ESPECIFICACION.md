# Especificación · Plataforma de encuestas de satisfacción CIS-SFP

Versión 3 · 13 de octubre de 2026. Fase 1. Cambios respecto a la versión 2: respuestas abandonadas (§2), etapas de familias, bloques de personal y escalas con texto (§2 y §4), etapas solapadas y reuniones de departamento (§5), coordinación y media del colegio (§6).

---

## 1. Alcance por fases

| Fase | Alcance |
|---|---|
| **1 (ahora)** | Resultados 2025/26 de alumnos, familias y personal; usuarios y roles; panel general con preguntas comunes; vista e informes PDF por profesor y por responsable |
| 2 | Gestión y publicación de encuestas propias: cuestionarios, asignación, enlace y QR, respuestas directas a la base de datos (mockup `referencia/mockups/Mockup_Encuestas_6_admin_encuestas.png`) |
| 3 | Histórico de todos los cursos y comparativa entre cursos |

Para que las fases 2 y 3 se construyan encima, el modelo de la Fase 1 debe cumplir tres cosas:
- preguntas con código estable (diccionario);
- el curso como dimensión en todas las tablas;
- cuestionarios versionados por curso.

---

## 2. Fuentes de datos (curso 2025/26)

Origen: SharePoint del colegio, sitio `sfpaula`, biblioteca `VdAE/Encuestas`. Rodrigo descarga los ficheros a `datos_locales/fuentes/`.

| Encuesta | Ficheros y cuestionarios | Notas |
|---|---|---|
| Alumnos | 6 cuestionarios: Primaria (Y2 a Y5), PAI asignaturas (Y6 a Y9), PAI competencias (Y6 a Y10), PAI asignaturas (Y10), Bachillerato (Y11), Bachillerato (Y12) | **Cada respuesta trae el grupo** (curso y letra, por ejemplo "Y9 A"). El bloque de profesorado se repite por asignatura. |
| Familias | 1 cuestionario (`Cliente_2526.xlsx`) | La familia marca el curso de cada hijo (selección múltiple), así que **una respuesta puede tener varias etapas**. Solo se guarda la etapa, no el curso. |
| Personal | Español (`Empleado_2526.csv`) e inglés (fichero Employees, pendiente) | Se unen en un solo conjunto. Segmentos: docente o no docente, antigüedad (primer año o más). **No se carga el sexo ni el bloque del Plan de Igualdad.** El fichero **no trae departamento ni equipo** de cada persona (§7.3). |

### Formato de Encuesta Fácil
- CSV o XLSX. Antes de los datos hay filas de metadatos, una fila con el **texto de la pregunta** y otra con la **opción o subtítulo** ("Respuesta", nombre de la asignatura…). Localízalas por contenido, no por posición.
- Cada pregunta de valoración tiene una columna con el **valor numérico** y otra con la etiqueta. Se usa el valor.
- **Escala general de 1 a 6.** NS/NC se reconoce **por su etiqueta "NS/NC"**, no por un número fijo: suele ser el 7, pero en la autoevaluación IB de Y12 es el 4 (su escala real es de 1 a 3). No cuenta en la media y se guarda como NS/NC.
- **Etiquetas:** su significado cambia entre ficheros ("Insatisfecho" es 2 en alumnos y 3 en familias). Las columnas que solo traen etiqueta, sin valor numérico (en personal: PEP, PAI, Perfil IB y reuniones de departamento), se convierten con la correspondencia etiqueta y valor **del mismo fichero**; una etiqueta desconocida detiene la carga.
- **Satisfacción general (alumnos):** una sola columna con valores de 1 a 6. El fichero no indica la escala; se trata como 1 a 6 y se marca "pendiente de confirmar".
- **Recomendación:** de 0 a 10 en alumnos, salvo Primaria (de 1 a 10); de 1 a 10 en familias y personal.
- **Autoevaluación IB (Bachillerato Y12):** escala de 1 a 3 ("En desarrollo", "Desarrollada", "Muy desarrollada") más NS/NC, que el fichero codifica como 4. No entra en medias generales. El prototipo contó ese 4 como valoración: sus medias de este bloque no son comparables.
- **Alumnos sin grupo:** algunas respuestas no indican grupo. Cuentan en el total del cuestionario y nunca forman un grupo propio.
- **"Lo más valorado":** selección múltiple, hasta tres aspectos por persona, con una lista de opciones común a los tres colectivos.
- **Preguntas duplicadas:** en profesorado aparecen preguntas con redacción casi igual (por ejemplo con "..." delante, o con "trabajdo" y "trabajado"). Se unifican en el diccionario.
- **Nombres de profesores:** los ficheros casi nunca los traen. La relación profesor, asignatura y grupo viene del Excel del colegio (§7.2).
- **Se descartan siempre:** identificador de respuesta, fechas y horas, IP, correo, nombre y apellidos, campos libres y parámetros de usuario, respuestas abiertas (incluidas "Otro, especifique" y los nombres de profesores), sexo, Plan de Igualdad, y datos que acotan a la persona sin estar en el alcance (nivel de tutoría y niveles en que imparte, segundo idioma, optativa, uso de transporte, comedor y canasto, curso de cada hijo).
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
- `opcion` (id, pregunta, codigo, texto_es, texto_en): opciones de selección múltiple ("Lo más valorado"), con su equivalencia en inglés
- `pregunta_cuestionario` (cuestionario, bloque, pregunta, orden, por_asignatura, por_departamento). Una pregunta no puede ser a la vez por asignatura y por departamento.
- `pregunta_comun` (codigo_comun, pregunta, colectivo): para el panel general (§7.1)
- `etapa` (Infantil, Primaria, PAI, Bachillerato)
- `grupo` (id, curso, etapa, nivel, nombre). **La etapa se obtiene siempre del grupo.**
- `asignatura` (id, curso, nombre normalizado)
- `departamento` (id, curso, nombre)
- `persona_responsable` (id, nombre, correo, departamento nullable)
- `cargo` (persona_responsable, curso, tipo: jefe_departamento, jefe_equipo o direccion, ambito)
- `asignacion_docente` (curso, grupo, asignatura, docente). **Clave primaria de las cuatro columnas:** admite varios docentes por asignatura y grupo (codocencia, desdobles).
- `respuesta` (id interno, cuestionario, grupo nullable, idioma_origen, docente, antiguedad, departamento_equipo). El grupo solo existe en alumnos (y puede faltar). Los segmentos de personal son columnas tipadas; no hay jsonb ni sexo.
- `respuesta_etapa` (respuesta, etapa): **solo familias**, una fila por etapa marcada. En alumnos la etapa se obtiene del grupo o del cuestionario.
- `respuesta_item` (respuesta, pregunta, asignatura nullable, departamento nullable, valor nullable, ns_nc). El departamento solo aparece en el bloque "Reuniones de departamento" de personal.
- `respuesta_opcion` (respuesta, pregunta, opcion)
- `usuario_perfil` (auth user id, nombre, rol, etapa nullable, activo, ultimo_acceso)
- `registro_actividad` (usuario, accion, detalle, fecha). **Solo se escribe desde el servidor** (dentro de las RPC o por trigger), nunca con un insert del cliente.

Ninguna política RLS permite `select` desde el cliente sobre `respuesta`, `respuesta_item` ni `respuesta_opcion`.

---

## 5. Anonimato: mínimo de 5 y supresión complementaria

1. **Mínimo:** ningún resultado agregado con n < 5. Se devuelve como suprimido, sin valor.
2. **Supresión complementaria:** cuando una vista enseña a la vez un total y sus partes (grupos de un cuestionario, asignaturas y grupos de un profesor, etapas, segmentos de personal), si **exactamente una** parte queda suprimida, se suprime también la siguiente parte más pequeña. Así no se puede deducir la parte oculta restando al total.
3. **Media global del profesor:** se calcula **solo con las combinaciones visibles**. El informe indica cuántas combinaciones se han excluido por tener menos de 5 respuestas.
4. **Filtros de personal:** un solo filtro a la vez (docente o no docente, antigüedad). No se combinan.
5. **Segmentos que siempre quedan ocultos** (familias de Bachillerato, con 3 respuestas): se muestran con un aviso explicando el motivo, no se omiten en silencio.
6. **Etapas solapadas (familias):** una familia cuenta en cada etapa que marcó y una sola vez en el total, así que las etapas no suman el total. La supresión complementaria se aplica igual entre etapas: si una sola etapa queda oculta, se oculta también la siguiente más pequeña.
   - **"Sin etapa":** las respuestas de familias sin ninguna etapa marcada forman una parte implícita "Sin etapa". Cuentan en el total, no se muestran como filtro ni como fila, pero participan en la supresión complementaria como una parte más: con menos de 5, cuenta como parte oculta; con 5 o más, como parte visible a efectos de la regla (y puede ser ella la que se oculte por complementaria), aunque siga sin mostrarse.
   - Ejemplo de 2025/26: "Sin etapa" (4) y Bachillerato (3) quedan ocultas; como ya hay dos partes ocultas, Infantil sigue visible. Si "Sin etapa" fuera 0, Bachillerato quedaría sola y se ocultaría Infantil, la siguiente más pequeña.
   - Como las etapas se solapan (familias con hijos en varias), la resta del total menos las partes visibles no da una cifra exacta de las ocultas. Aun así, la regla se aplica igual, por prudencia.
   - En la vista, junto al número de respuestas, una nota informa de las familias sin etapa con el mismo criterio que cualquier parte: "menos de 5" mientras sean menos de 5, la cifra exacta si su parte es visible y "5 o más" si se oculta por complementaria.
7. **Reuniones de departamento (personal):** el departamento es una dimensión del ítem. El bloque solo se consulta repartido por departamento, con el mínimo de 5 y la complementaria. Ninguna RPC lo cruza con otras respuestas de la misma persona: no admite filtros de segmento y el departamento no sirve para filtrar otros bloques ni para contar personas.
8. **Presentación de lo oculto:** "menos de 5" cuando la parte tiene menos de 5 respuestas; "oculto" cuando es por supresión complementaria, con aviso y leyenda "oculto para proteger el anonimato". En los PDF, nota al pie.
9. **Ámbitos de responsables** (departamento, equipo): mismas reglas. Con equipos de menos de 5 personas, el resultado se oculta y el informe lo dice.
10. Todo lo anterior se aplica dentro de las RPC, y por tanto también en CSV y PDF.

Tests obligatorios: una batería de casos en `supabase/tests` que intente saltar la regla por resta y por combinación de filtros.

---

## 6. Roles y permisos (Fase 1)

| | Administrador | Dirección | Coordinación de etapa |
|---|---|---|---|
| Panel general | Todo | Todo | Solo alumnos y familias de su etapa; sin personal |
| Alumnos | Todo | Todo | Solo los cuestionarios de su etapa |
| Familias | Todo | Todo | Solo su etapa |
| Personal | Todo | Todo | Sin acceso |
| Vista e informes de profesor | Sí | Sí | **Solo profesores con docencia en su etapa**, y solo con los resultados de esa etapa. Ve también la media del colegio como referencia |
| Vista e informes de responsables | Sí | Sí | No |
| Usuarios y registro de actividad | Sí | No | No |

Correspondencia de cuestionarios con etapas:
- Primaria (Y2 a Y5) → Primaria.
- Los tres de PAI → PAI.
- Los dos de Bachillerato → Bachillerato.
- La coordinación de Infantil solo ve familias de Infantil, porque no hay encuesta de alumnos de Infantil.

Profesores y jefes no tienen cuenta en la Fase 1: reciben su informe en PDF.

---

## 7. Funcionalidades

### 7.1 Panel general (inicio tras el login)
1. **Recomendación del colegio por colectivo:**
   - barra 100 % apilada (detractores, neutros y promotores) con NPS;
   - **alumnos se muestra en dos barras**, Primaria por un lado y PAI y Bachillerato por otro, porque tienen escalas distintas y resultados muy diferentes;
   - la media de recomendación aparece como dato secundario, con una nota sobre las escalas.
2. **Preguntas comunes:** barras agrupadas con la media de 1 a 6 de cada colectivo en las preguntas compartidas. Candidatas, a confirmar con el colegio y cargar en `pregunta_comun`:
   - En los tres colectivos: "El ambiente del Colegio es de respeto y convivencia".
   - Familias y personal: competencia profesional del profesorado; apoyo personal y académico del profesorado; atención a las necesidades individualizadas; valores éticos; el modelo educativo prepara para el futuro; mentalidad internacional; innovación; lectura; artes; música; competencias digitales; cultura; enseñanza de idiomas; Biblioteca; acceso a la primera opción de carrera; conciencia medioambiental.
   - Alumnos y familias: servicios (Comedor, Canasto, Biblioteca, Limpieza, Portería, Secretaría Académica, Servicio de Orientación y Transporte), y "Los recursos usados favorecen el aprendizaje".
3. **Lo más valorado por colectivo:** porcentaje de personas que eligen cada aspecto, comparado entre los tres colectivos.
4. **Indicadores por colectivo:** respuestas, satisfacción general, recomendación y NPS.
5. **Opcional, construir solo si Rodrigo lo confirma:** "qué pesa más en la recomendación", la correlación entre la media de cada bloque y la recomendación de cada persona, con un mínimo de 30 respuestas.

### 7.2 Vista e informe de profesor
- Buscador de profesor. Muestra los resultados de las encuestas de alumnos de sus asignaturas y grupos:
  - media por asignatura y grupo;
  - media global (§5.3);
  - detalle por pregunta;
  - comparación con la media de su etapa y la del colegio.
- **PDF por profesor:** descarga individual y en lote (ZIP, `Informe_2526_Apellido_Nombre.pdf`), con el estilo del colegio. La generación queda en el registro de actividad.
- **Depende del Excel del colegio** (`etl/plantillas/asignacion_docente.xlsx`), con columnas: curso, grupo, asignatura, docente, correo del docente y **departamento**. Hasta tenerlo, se construye con datos de ejemplo.
- La asignatura del Excel se casa con la asignatura normalizada de los cuestionarios. Las que no casen se listan en un informe de la carga para revisarlas a mano.

### 7.3 Vista e informes de responsables: jefe de departamento, jefe de equipo y dirección
- El personal valora a su jefe en el bloque **"Superiores"** (7 preguntas: trato, dirección del equipo, trabajo en equipo, escucha, reconocimiento, comunicación descendente y comunicación ascendente).
- **Primer paso, bloqueante:** comprobar si el fichero de personal 2025/26 trae el departamento o el equipo de cada persona.
  - **Si lo trae:**
    - vista e informe PDF por responsable (individual y en lote) con el bloque Superiores de su ámbito;
    - los jefes de departamento ven además la media de los profesores de su departamento en las encuestas de alumnos, gracias a la columna de departamento del Excel.
  - **Si no lo trae:**
    - para 2025/26 se muestra el bloque Superiores agregado (todo el personal, y por docente y no docente);
    - el modelo queda preparado para 2026/27, cuando la Fase 2 preguntará el departamento o equipo;
    - el informe explica la limitación.
- **Resultado de la comprobación (13/10/2026): el fichero de 2025/26 no lo trae.** Se aplica el plan alternativo: Superiores agregado y `departamento_equipo` vacío. No se deduce la pertenencia a un departamento a partir de qué columnas rellenó cada persona.
- **Bloques que sí existen en 2025/26:**
  - **Reuniones de departamento:** 21 afirmaciones sobre las reuniones de cada departamento y sobre su jefe (trato, dirección, trabajo en equipo, reconocimiento, comunicación), contestadas solo por sus miembros. Hay 8 departamentos. Se carga con el departamento como dimensión del ítem y solo se expone agregada por departamento (§5.7), en el informe del jefe de departamento y en la vista de personal.
  - **Equipo de Individualización:** 22 afirmaciones que contestan los tutores sobre sus reuniones y sobre su jefe de equipo (trato, dirección, trabajo en equipo, reconocimiento, comunicación). Va en el informe de ese jefe de equipo.
- **Dirección:** su informe incluye el bloque Superiores del conjunto y la valoración del centro por parte del personal.

### 7.4 Vistas por colectivo
Se porta el prototipo `datos_locales/Tablero_Encuestas_2526_CIS-SFP.html`, que funciona con datos reales y ya tiene el estilo de la intranet. Se respetan las reglas nuevas: supresión complementaria, sin sexo y un filtro a la vez en personal.

- **Alumnos:**
  - filtros de cuestionario y grupo, e indicadores;
  - profesorado por asignatura, tabla de colores de asignatura por grupo y satisfacción por bloque;
  - detalle por pregunta, puntos fuertes y de mejora;
  - recomendación y lo más valorado.
- **Familias:**
  - filtro por etapa, con aviso en Bachillerato;
  - valoración general del centro destacada, también comparada por etapa;
  - bloques, detalle, recomendación y NPS, y lo más valorado.
- **Personal:**
  - filtro de **docente o no docente** y filtro de antigüedad, nunca combinados;
  - indicadores y eNPS;
  - dimensiones, detalle, recomendación y lo más valorado;
  - en pequeño junto a las respuestas, el número de personas por idioma, como dato informativo. Se calcula de los datos cargados (personas con alguna respuesta válida y con su segmento indicado): hoy **"62 en español"**; con el cuestionario en inglés, **"62 en español · N en inglés"**. Los resultados van siempre unidos: las preguntas en inglés se mapean al mismo diccionario.

### 7.5 Usuarios y administración
Funciones del mockup `referencia/mockups/Mockup_Encuestas_5_admin_usuarios.png`; el estilo es el de la intranet.
- Alta por invitación con nombre, correo, rol y etapa.
- **Caducidad del enlace:** Supabase limita la validez de los enlaces de correo (como máximo 24 horas, compruébalo en la versión actual). Se usa el máximo permitido y el botón "Reenviar invitación". El texto de la interfaz dirá la caducidad real, no 72 horas.
- Desactivar, reactivar y reenviar invitación. Último acceso y aviso a los 90 días sin entrar.
- Registro de actividad, escrito por el servidor: invitaciones, cambios de rol, desactivaciones, exportaciones e informes generados.
- Doble factor (TOTP) obligatorio para administradores.

### 7.6 Exportación
- CSV por vista, generado por las RPC y sujeto a todas las reglas del §5.
- PDF de cada vista.
- Nunca se exportan respuestas individuales.

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
- **Colores de los gráficos:**
  - desacuerdo en tonos de `--warn` mezclados con blanco;
  - acuerdo en `--sky`, `--brand` y `--navy`;
  - neutros en `--muted` mezclado con blanco.
  Ya están resueltos en el prototipo con las clases `en-n1..3`, `en-p1..3` y `en-c1..7`.
- **Responsive:** móvil, iPad y escritorio, con los puntos de corte de la plantilla (1260, 900, 620 y 600 px).
- **Accesibilidad:** botones y enlaces reales, foco visible, `alt` en las imágenes y etiquetas visibles en los formularios.
- **PDF:** mismo estilo (logo del colegio, colores y tipografía) y generación en lote. La librería es libre.

---

## 9. Plan de trabajo

1. Repositorio y `.gitignore` (como mínimo `datos_locales/`, `.env*` salvo `.env.example`, `node_modules/` y `dist/`). README y estructura del proyecto. `docs/PROGRESO.md`.
2. Supabase (Frankfurt): migraciones, RLS, RPC con el §5 y tests de anonimato.
3. ETL de los seis cuestionarios de alumnos, el de familias y el de personal (español e inglés unidos). Diccionario y validación contra `datos_locales/validacion_2526.md`. **No se avanza hasta que cuadre.** En este paso se verifica también si personal trae departamento o equipo (§7.3).
4. Auth, perfiles, roles, invitaciones y doble factor de administrador.
5. Diseño de la intranet y vistas por colectivo (portando el prototipo).
6. Panel general.
7. Vista e informes de profesor: primero con datos de ejemplo y después con el Excel.
8. Vista e informes de responsables, según el resultado del paso 3.
9. Admin de usuarios y registro de actividad.
10. Despliegue, dominio, pruebas en móvil e iPad, manual del administrador y guía de usuario.

Commits pequeños. Al cerrar cada paso, actualiza `docs/PROGRESO.md`.

---

## 10. Pendientes y preguntas abiertas

| # | Tema | Quién | ¿Bloquea? |
|---|---|---|---|
| 1 | Descargar las exportaciones 2025/26 de SharePoint a `datos_locales/fuentes/` | Rodrigo | Paso 3 |
| 2 | Excel de profesores por asignatura y grupo, con correo y departamento | Colegio | Paso 7, con datos reales |
| 3 | ¿El fichero de personal trae departamento o equipo? Lista de jefes y su ámbito | Verificar en el paso 3 y preguntar al colegio | Paso 8 |
| 4 | ¿Acepta el colegio Supabase o pone su backend? | Rodrigo con sistemas | No (lógica aislada en `src/data/`) |
| 5 | Lista definitiva de preguntas comunes | Colegio | No |
| 6 | Escala de la satisfacción general de alumnos | Colegio | No |
| 7 | ¿Los PDF los envía el colegio o la plataforma por correo? Por defecto, solo descarga | Rodrigo | No |
| 8 | Idiomas: ¿entra el inglés en la Fase 1? | Rodrigo | No |
| 9 | Registros DNS para el dominio y el remitente | Sistemas del colegio | Paso 10 |
| 10 | ¿Construir el análisis de "qué pesa más en la recomendación"? | Rodrigo | No |

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
