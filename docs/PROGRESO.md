# Progreso

Plan de trabajo en `docs/ESPECIFICACION.md` §9.

| Paso | Estado |
|---|---|
| 1. Repositorio, estructura, README, PROGRESO | Hecho |
| 2. Supabase local: migraciones, RLS, RPC, tests de anonimato | Hecho en local; proyecto en la nube creado en Irlanda (UE) y enlazado el 22/10/2026 |
| 3. ETL y validación | Hecho (validación completa en verde; falta el cuestionario de personal en inglés) |
| 4. Auth, perfiles, invitaciones, doble factor | Hecho en local (falta Brevo, en el despliegue) |
| 5. Diseño de la intranet y vistas por colectivo | En curso: alumnos, familias y personal hechas en local |
| 6. Panel general | Hecho en local (preguntas comunes candidatas, pendientes de confirmar) |
| 7. Vista e informes de profesor | Hecho con la asignación real de Alexia (en local); falta que el colegio confirme los departamentos |
| 8. Informes de responsables | Hecho: Equipo de Individualización, departamentos con 5 o más y Superiores (no docentes); vista y PDF |
| 9. Administración de usuarios y registro | Hecho en local |
| 10. Despliegue | Plan preparado (`docs/DESPLIEGUE.md`); pendiente de las decisiones y cuentas de Rodrigo |

## Paso 1 · Repositorio (13/10/2026)

- Repositorio git en `main`, remoto `origin` en `NiageCH/Encuestas_Aonia` (privado).
- `.gitignore`: `datos_locales/`, `.env*` (salvo `.env.example`), `node_modules/`, `dist/`, temporales de Supabase y Python, y cualquier `.csv` o `.xlsx` fuera de `etl/plantillas/`.
- Estructura `src/data/`, `etl/plantillas/`, `supabase/`, `docs/`.
- README con la comprobación previa a cada push.

## Paso 2 · Supabase en local (13/10/2026)

Hecho:
- CLI de Supabase como dependencia de desarrollo (`npx supabase`, versión 2.120). Postgres 17.
- Puertos locales 554xx, porque en el equipo hay otro proyecto Supabase con los puertos por defecto.
- `config.toml`: alta libre desactivada, TOTP activado, enlaces de correo de 24 horas (`otp_expiry = 86400`), contraseñas de 10 caracteres como mínimo con letras y números.
- Migraciones:
  1. `catalogo`: modelo del §4 (curso en las tablas de catálogo, pregunta sin curso, escala en la pregunta, `opcion`, `asignacion_docente` con clave de cuatro columnas). Trigger: un bloque no mezcla escalas.
  2. `respuestas`: esquema `privado` (no expuesto por la API) con RLS sin políticas. Segmentos de personal en columnas tipadas (`docente`, `antiguedad`, `departamento_equipo`); sin sexo. Triggers de integridad: grupo o etapa según el colectivo, valor dentro de la escala, asignatura si y solo si la pregunta es por asignatura.
  3. `usuarios_permisos`: `usuario_perfil`, `registro_actividad` (solo escritura desde el servidor), esquema `permisos` con las funciones de rol, RLS en todas las tablas de `public`. El administrador necesita `aal2`.
  4. `motor_anonimato`: resolución del filtro con permisos, cálculo de celdas con `GROUPING SETS` y supresión (mínimo de 5 y complementaria iterativa en filas, columnas y márgenes).
  5. `rpc_resultados`: `resultados`, `resumen`, `detalle_preguntas`, `listar_profesores`, `resultados_profesor`. Solo `authenticated`.
- Tests pgTAP (109, todos en verde): acceso, anonimato, cálculos, profesor y roles, integridad de la carga.
- `supabase/scripts/probar_mfa_local.py`: prueba de principio a fin del doble factor contra la API local.

Decisiones de diseño:
- **Filtro = parte de su partición.** Un filtro que selecciona una parte (grupo, asignatura, etapa en familias, segmento de personal) se calcula como dimensión del conjunto completo. Así una parte suprimida por complementaria sigue suprimida si se pide sola.
- **La complementaria se aplica en líneas con el total visible.** Si el total de una fila o columna ya está oculto, sus partes no se fuerzan (no se pueden deducir por resta).
- **Las partes suprimidas no devuelven n, media ni distribución.** Motivos: `menos_de_5`, `complementaria` o `sin_datos`. La vista mostrará "menos de 5" solo en el primero.
- **Vista de profesor:** cada combinación asignatura y grupo toma su estado de la tabla asignatura por grupo de su cuestionario. La media global se calcula con las combinaciones visibles, ponderada por valoraciones (equivale a la media agrupada).
- **Coordinación en la vista de profesor:** recibe la media de su etapa, pero no la del colegio (la tabla del §6 dice "solo los resultados de esa etapa"). **A confirmar con Rodrigo.**
- **"Lo más valorado":** porcentaje sobre quienes contestan la pregunta, como el `topn` del prototipo.
- **Administrador sin `aal2`:** puede leer su propio perfil (para que la interfaz sepa que debe pedir el código), pero ninguna RPC ni ningún otro dato.

Pendiente del paso 2:
- ~~Crear el proyecto en la nube y enlazarlo~~ Hecho el 22/10/2026 (Irlanda, UE, plan Free). La decisión del colegio sobre Supabase sigue pendiente.
- RPC de exportación CSV con registro de actividad (se hará con las vistas, pasos 5 y 6).
- `ultimo_acceso` y aviso de 90 días (paso 4).
- Forma de carga de la ETL: conexión directa a Postgres o RPC de carga solo para `service_role` (paso 3).

Notas técnicas:
- En `config.toml`, `[auth.email] enable_signup` debe quedar en `true`: en `false` desactiva también el login con correo. El alta libre se bloquea con `[auth] enable_signup = false`.

## Paso 3 · ETL y validación (13 y 14/10/2026)

Hecho:
- `etl/encuesta_facil.py` (lectura de CSV y XLSX, normalización), `etl/cuestionarios_2526.py` (reglas por fichero: cada columna se carga o se descarta con motivo; una columna sin regla detiene la carga), `etl/cargar_2526.py` (carga repetible en una transacción, informe en `datos_locales/informes/`) y `etl/validar_2526.py` (compara las RPC con los agregados del prototipo).
- Carga local: 8 cuestionarios, 890 respuestas, unas 132.000 valoraciones, 340 preguntas en el diccionario.
- Migración 7: `respuesta_etapa` (familias con varias etapas), departamento como dimensión del ítem, bloque de reuniones de departamento aislado, alumnos sin grupo, n = personas con alguna respuesta válida.
- Validación: tabla de control, 494 preguntas, asignaturas, grupos, etapas y segmentos; todo cuadra con los criterios acordados.
- Tests: 133 en verde. Los datos de los tests usan un curso ficticio (2000/01) para convivir con la carga real.

Decisiones (14/10/2026):
- Abandonadas: se cargan con lo que contestaron; n = personas con alguna respuesta válida.
- Profesorado: media agrupada (§3). El prototipo publicó otra fórmula; brecha máxima 0,011, que cambia la cifra redondeada de un cuestionario (valores en `datos_locales/validacion_2526.md`).
- Media de grupo: todas sus valoraciones. Test de que la resta no destapa una celda oculta.
- Personal: se excluye la respuesta sin segmento (1). Los valores de control de personal se recalcularon (en `datos_locales/validacion_2526.md`).
- Departamento en personal: no viene; plan alternativo del §7.3. Sí se cargan las reuniones de departamento (21 afirmaciones × 8 departamentos) y el bloque del Equipo de Individualización (18 tutores).

Pendiente del paso 3:
- Cuestionario de personal en inglés: falta el fichero y la correspondencia de sus textos (`TEXTOS_PERSONAL_EN`).
- Lista definitiva de preguntas comunes para `pregunta_comun` (paso 6).

## Paso 5 · Vistas (14/10/2026, en curso)

Hecho:
- Frontend Vite + React + TypeScript con los bloques A y B de la plantilla (`scripts/extraer_plantilla.py`), estilos propios `en-`, textos en `src/i18n.ts` y acceso a datos solo en `src/data/`.
- Acceso provisional con correo y contraseña (usuarios locales con `supabase/scripts/crear_usuario_local.py`).
- Menú: Inicio · Alumnos · Familias · Personal, y Usuarios para administradores (§7.0). Personal tiene dos apartados: Encuesta de personal (filtros de uno en uno) e Informes por persona por jerarquía (Dirección, Equipos, Departamentos, Profesores), cada nivel con su PDF. La coordinación solo ve Informes por persona → Profesores de su etapa.
- Alumnos: filtros de cuestionario y grupo, indicadores, profesorado por asignatura, bloques y recomendación.
- Familias: etapas (con la parte implícita «Sin etapa», §5.6), valoración general destacada y por etapa, bloques, detalle por pregunta, recomendación y lo más valorado.
- Personal: un filtro a la vez (docentes, no docentes, antigüedad), eNPS, dimensiones, Superiores (solo lo contestó el personal no docente), reuniones de departamento por departamento, Equipo de Individualización, detalle, recomendación, lo más valorado y dato de idioma.
- Información emergente en todos los gráficos, también con teclado.
- Migración 8: idioma como clave de partición de personal y `cuestionario.idiomas_cargados`.
- Tests: 142 en verde.

- Recomendación (§7.8): reparto como dato principal e «Índice de recomendación» como secundario, sin siglas.
- Idioma de personal: recuento informativo exacto (`recuento_idiomas`), fuera de la supresión (§5.11); no es filtro (migración 9).
- Panel general (paso 6): indicadores por colectivo, recomendación comparada con barras de reparto (alumnos en dos: Primaria y PAI con Bachillerato, migración 10), 26 preguntas comunes candidatas (`etl/preguntas_comunes_2526.py`) y lo más valorado comparado.

- Plantilla de asignación para el colegio: `etl/plantillas/asignacion_docente_2526.xlsx` (curso, grupo, asignatura, apellidos, nombre, correo, departamento; hojas de instrucciones y listas). Carga con `etl/cargar_asignaciones.py` (lo que no casa va a un informe para revisarlo a mano).
- Vista de profesor (paso 7) en Personal → Informes por persona → Profesores: buscador, combinaciones asignatura y grupo, media global con las visibles, comparación con etapa y colegio, detalle por pregunta. La coordinación solo ve a los profesores de su etapa. Probada con 193 docentes inventados (`etl/ejemplo_asignaciones.py`, en `datos_locales/`).

- PDF por profesor (paso 7): individual y en lote (ZIP, `Informe_2526_Apellidos_Nombre.pdf`), con cabecera del colegio, Raleway y colores de la intranet, y nota al pie de lo oculto. Datos de la RPC `informe_profesor` (migración 11), que deja cada generación en el registro de actividad, marcando el lote.

- Responsables (paso 8), ahora dentro de Personal → Informes por persona (Dirección: Superiores y valoración del centro; Equipos; Departamentos: reuniones y media de sus profesores según los alumnos, migración 14). Informes por ámbito: Equipo de Individualización (tutores), cada departamento con su resultado visible y Superiores (personal no docente, con la nota de que no se puede atribuir a un jefe concreto). Vista y PDF individual; RPC `informe_responsable` (migración 12) con registro de actividad al generar el PDF.

## Pasos 4 y 9 · Acceso y administración de usuarios (15/10/2026)

- Invitación por correo (Edge Function `admin-usuarios`, solo administradores con aal2): crea el perfil con rol y etapa y lo registra; reenvío para quien no ha entrado; nunca duplica ni borra a un usuario ya existente (un primer diseño sí lo hacía y lo detectó la prueba).
- Pantallas: crear contraseña al aceptar la invitación, recuperar contraseña, doble factor de administradores (QR la primera vez, código después).
- «Usuarios» (solo administradores): indicadores del mockup, tabla con rol, estado, último acceso, aviso a los 90 días y doble factor; cambiar rol y etapa, desactivar y reactivar (con confirmación), reenviar invitación; registro de actividad legible.
- Migración 13: último acceso por disparador, RPC de administración con reglas (no desactivarse ni quitarse el rol a uno mismo, siempre un administrador activo) y registro de cada cambio.
- Plantillas de correo en español; enlaces de 24 horas.
- Pruebas: 174 tests SQL y `supabase/scripts/probar_invitacion_local.py` (17 comprobaciones de principio a fin).

Pendiente: Excel de asignación del colegio, revisión en móvil e iPad; en el despliegue, Brevo y el remitente.

## Navegación de Personal (15/10/2026)

- `src/navegacion.ts`: rutas, direcciones antiguas (`#/profesorado`, `#/responsables`) y permisos por rol; 10 tests con `npm test` (vitest).
- `supabase/tests/08_personal_informes.sql`: lo que cada rol puede pedir al servidor en la nueva navegación (la coordinación, solo Profesores de su etapa) y la media de departamento según los alumnos (solo combinaciones visibles).
- Total: 194 tests SQL y 10 de navegación.

## Asignación real de profesores (20/10/2026)

- El colegio entrega el listado de Alexia (grupos, asignaturas y docentes de 2025/26), en `datos_locales/fuentes/`. No trae departamento.
- `etl/convertir_alexia_2526.py` lo pasa al formato de la plantilla:
  - Equivalencias por cuestionario: las encuestas agrupan varias materias de Alexia en una pregunta («Lengua española o lengua adaptada»).
  - No se cargan tutorías, refuerzos, CICE, Mindfulness, Unidad de Indagación, Aprendizaje Interdisciplinario, Música PIM de Primaria, Monografía y similares, porque los alumnos no las valoran.
  - No se atribuyen «Inmersión lingüística» ni «Optativa» de la encuesta: sus grupos no son grupos de clase.
  - Departamento propuesto por lo que imparte cada docente (26 a revisar), en la hoja «Departamentos», que manda al cargar.
- Cargado en local: 97 docentes, 799 filas, 396 combinaciones grupo y asignatura, 135 con varios docentes (cada docente recibe el resultado de la combinación).

## Respuestas del colegio (21/10/2026)

Recibidas. Los datos personales (usuarios iniciales, contacto técnico, jefes de departamento y del Equipo de Individuación) están en `datos_locales/responsables_2526.xlsx`, fuera de git. Especificación actualizada (§4, §5.9, §5.12 a §5.14, §7.0, §7.2, §7.3, §7.5 y §10).

Decidido por el colegio:
- Nombres oficiales de los nueve departamentos y «Equipo de Individuación».
- Informe de departamento por jefe, con sus departamentos dentro.
- Informe de profesor con «Sus clases» y «Valoraciones compartidas»; media global solo con las propias; los dados de baja se incluyen.
- Acceso con correo y contraseña; Microsoft queda para más adelante, con la autenticación aislada.

Análisis hechos, a la espera de decisión (§10, puntos 11 a 14):
- Atribución por el nombre del profesor (Y10 a Y12) y de la optativa (Y6 a Y9).
- Equipo de Individuación por jefe con el tramo de tutoría.
- Los dos departamentos de un mismo jefe, juntos.
- Huecos de Alexia en Inglés de Y10 y Y12.

Hecho (21/10/2026, fases A y B del plan):
- Migración 16: departamentos oficiales y su equivalencia con la encuesta, situación de cada docente, tramo de tutoría y atribución a un docente, clases propias, compartidas y atribuidas, informes por jefe y por tramo, conjuntos de partes ocultas.
- Carga: `etl/departamentos_2526.py` (nombres oficiales y equivalencias), `etl/convertir_alexia_2526.py` (aplica la revisión del colegio y reparte Inglés y Adquisición; los 9 dudosos, donde más clases dan, con un Excel para el colegio), `etl/atribucion_2526.py` (nombre del profesor y optativa) y `etl/cargar_responsables.py` (jefes y responsables del equipo, desde `datos_locales/responsables_2526.xlsx`).
- En local: 9 cargos de jefe de departamento y 4 del equipo; tramos 7, 5, 4 y 2; 331 respuestas atribuidas (Inglés de Y10 y Y12 sin atribuir).
- Vistas y PDF: informe del profesor con «Sus clases» y «Valoraciones compartidas»; Departamentos por jefe (un PDF por persona con sus departamentos); Equipos con todo el equipo y cada tramo (el compartido, con nota); «Individuación» en todos los textos.
- Tests: 234 SQL (40 nuevos, entre ellos que el tramo no es accesible desde ninguna otra RPC) y 10 de navegación. Las migraciones se aplican desde cero sin errores.

Respuestas del colegio del 22/10/2026:
- Lengua y Literatura Inglesas y Adquisición de Lenguas van unidos, como Artes Visuales y Tecnología con Educación Física: los 9 docentes dudosos no necesitan revisión.
- Inglés de Y10 y Y12: sustituciones por bajas. La valoración va al profesor nombrado aunque no sea el titular (migración 17). Inglés de Y12, atribuido; en Y10 D falta un docente que no está en Alexia (plantilla en `datos_locales/docentes_adicionales_2526_plantilla.xlsx`).
- Inicio de sesión con la nueva intranet: se verá más adelante; la autenticación sigue aislada en `src/data/sesion.ts`.
- En local: 388 respuestas atribuidas. Tests: 237 SQL.

Orden de carga: `cargar_2526.py` → `convertir_alexia_2526.py` → `cargar_asignaciones.py` → `cargar_responsables.py`.

## Bloqueos

- Cuestionario de personal en inglés (4 respuestas).
- Inglés de Y10 D: nombre y correo del docente que no está en Alexia (sustitución).
- Departamento o equipo en el fichero de personal: se verifica en el paso 3.
