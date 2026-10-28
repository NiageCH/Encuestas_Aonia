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
- ~~RPC de exportación CSV con registro de actividad~~ Hecho el 22/10/2026 (migración 23).
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

- `src/navegacion.ts`: rutas, direcciones antiguas (`#/profesorado`, `#/responsables`) y permisos por rol; 10 tests (12 desde el 22/10/2026) con `npm test` (vitest).
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

Supabase en la nube (22/10/2026, Irlanda, plan Free, sin datos reales):
- 17 migraciones aplicadas. Tests contra la nube: 241 en verde, sin dejar ningún registro (recuento de las 26 tablas, Auth incluido, idéntico antes y después). Los tests preparan los datos como postgres y comprueban como anon y authenticated (hay tests que lo verifican).
- Seguridad: RLS en las 24 tablas; el esquema privado no está expuesto por la API (solo public y graphql_public) y anon no lee ni ejecuta nada. Revisor de Supabase: sin errores; avisa de las funciones security definer (intencionado, regla 3) y de una política mejorable (migración 18, preparada en local).
- Función admin-usuarios subida y activa (exige sesión). Falta el secreto SITIO_URL cuando haya alojamiento.
- Correo: el de Supabase por defecto, solo para pruebas internas, hasta tener encuestas@sfpaula.com. No se invita a nadie del colegio.

Web de pruebas (22/10/2026): Clever Cloud, región París, aplicación `Encuestas-SFP`, desplegada desde el equipo de Rodrigo con clever-tools (versión f075817). Cabeceras de seguridad comprobadas desde fuera. Subdominio `encuestas-sfp.niage.eu` con su CNAME; certificado de Let's Encrypt en curso.

Acceso en la nube (22/10/2026): configuración de Auth en `supabase/config.toml`, sección `[remotes.pruebas]`, aplicada con `npx supabase config push` tras revisar `npx supabase config diff`. Alta libre e inicio anónimo desactivados (comprobado), enlaces de 24 horas, contraseñas de 10 con letras y números, plantillas en español con pie de contacto, Site URL y Redirect URLs del subdominio. El SMTP de Brevo no se declara en el repositorio: vive solo en el panel. Invitación de prueba enviada a rodrigo@niage.es (sin perfil todavía).

Decisión del 22/10/2026: no se cargan datos inventados en la nube; las pruebas con el colegio serán con los datos reales de 2025/26, cuando el colegio lo autorice. Preparado: carga, validación contra la nube (`validar_2526.py --remoto`) y borrado (`borrar_2526.py`), en `docs/DESPLIEGUE.md` §5. Estado vacío en todas las pantallas de resultados y franja «Resultados en validación» en la aplicación y los PDF (se quita con `VITE_AVISO_VALIDACION=no`).

Carga real en la nube (22/10/2026, con autorización escrita del colegio): migración 20 y web desplegadas; encuestas, asignaciones y responsables cargados. Validación contra la nube idéntica a `validacion_2526.md` (sin diferencias) y recuento idéntico al local; tests en la nube en verde sin dejar registros. Revisión interna en curso (lista en `datos_locales/Revision_interna_2526.xlsx`, PDF en `datos_locales/informes/revision_2526/pdf/`); no se invita a nadie del colegio todavía.
- Fallos encontrados al preparar la revisión y corregidos en local (migración 21, 251 tests): el informe de 10 profesores daba error (pregunta que no está en todos sus cuestionarios con atribuciones en otro) y la optativa salía también grupo a grupo, contando doble en la media global. Pendiente de subir a la nube.

Panel de Inicio con puntos de mejora (22/10/2026, migración 22): puntos fuertes y de mejora por colectivo, «En qué se diferencian quienes no recomendarían el Colegio» y «Lo menos elegido». 273 tests (22 nuevos en `10_panel_mejora.sql`).

Exportación de cada vista (22/10/2026, migración 23, §7.6): botones «CSV para Excel» y «PDF» en el Panel general, Alumnos, Familias y Personal, con lo que se ve en pantalla y los filtros activos (Familias y Personal, con el detalle de todos los bloques). Los datos salen de las mismas RPC que la pantalla; `registrar_exportacion` deja cada exportación en el registro de actividad (vista, formato y filtros) y rechaza a quien no puede ver la vista. CSV en UTF-8 con BOM, punto y coma y coma decimal, comprobado abriéndolo con Excel en macOS (es_ES). Celdas ocultas con «menos de 5», «oculto» o «sin datos», nunca en blanco. Cabecera con colegio, curso, vista, filtros, fecha y la franja de validación si está activa. Archivos `Encuestas_2526_<Vista>[_<Filtro>].csv|pdf`. 289 tests de base de datos (16 nuevos en `11_exportacion.sql`) y 9 del CSV (`src/exportacion/csv.test.ts`). Subida el 22/10/2026: GitHub (ac51a94), migración 23 en la nube con 289 tests en verde y recuento sin cambios, y web desplegada.
- Quedaba pendiente desde el paso 2 («RPC de exportación CSV con registro de actividad») y no se hizo al cerrar las vistas.

«Informes por persona» en el menú de arriba (22/10/2026): Inicio · Alumnos · Familias · Personal · Informes por persona · Usuarios. Dentro, Dirección, Equipos, Departamentos y Profesores; la coordinación entra directamente en Profesores y ya no ve la entrada Personal. Personal queda como la encuesta, con un enlace corto a la nueva sección. Direcciones nuevas `#/informes/<nivel>`; las antiguas (`#/personal/informes/<nivel>`, `#/profesorado`, `#/responsables`) llevan a su sitio. 12 tests de navegación.

Paso de encuestas-sfp.niage.eu a encuestas.sfpaula.com (cuando el colegio publique su DNS):
- DNS del colegio: CNAME `encuestas` → `domain.par.clever-cloud.com.` (lo crea su contacto técnico).
- Clever Cloud: añadir `encuestas.sfpaula.com` a la aplicación (certificado automático) y, cuando funcione, quitar el subdominio de Niage.
- Supabase: `SITIO_URL=https://encuestas.sfpaula.com`; Auth → Site URL y Redirect URLs con `https://encuestas.sfpaula.com/**`, quitando las de niage.eu.
- Correo: dominio `sfpaula.com` en Brevo con sus registros (verificación, DKIM, DMARC; revisar el SPF y el DMARC que ya tenga el colegio para no romper su correo), remitente `encuestas@sfpaula.com` (buzón que crea su contacto técnico) en el SMTP de Supabase. Retirar `niage.eu` de Brevo y sus registros DNS si ya no se usan.
- Plantillas de correo (`supabase/templates/` y panel de Supabase): cambiar el pie «Para cualquier duda, escribe a rodrigo@niage.es» por el contacto que decida el colegio.
- Cabeceras: el Caddyfile no cambia (toma la dirección de Supabase de la variable del alojamiento).
- Plan Pro de Supabase antes de las pruebas con el colegio.
- Invitaciones enviadas antes del cambio: sus enlaces llevan al subdominio de Niage; reenviarlas tras el cambio.

Orden de carga: `cargar_2526.py` → `convertir_alexia_2526.py` → `cargar_asignaciones.py` → `cargar_responsables.py`.

## Ajustes de coordinación e identificadores (rama `fase1-coordinacion`, 26/10/2026)

- Migración 24: identificador aleatorio en `privado.respuesta` y `respuesta_item`; las respuestas existentes se renumeran y se reescriben en orden aleatorio en la misma transacción (probado sobre los datos reales: recuento y validación idénticos, ningún identificador consecutivo).
- Migración 25: referencia del colegio en Familias para la coordinación (`"referencia": true` en el filtro, solo el total, sin filtros ni repartos).
- Familias, coordinación: mensaje con curso y etapa cuando su etapa no llega a 5, bloque «Referencia: familias de todo el Colegio» y marca de la media del colegio en cada bloque; también en el CSV y el PDF.
- Mensajes revisados (26/10/2026): «En 2025/26 respondieron menos de 5 familias de [etapa]. Con menos de 5 no se muestran resultados, para proteger el anonimato» para cualquier rol que elija esa etapa; por supresión complementaria, el texto de la resta. La referencia del colegio dice claramente que no es de su etapa. Alumnos: ninguna etapa ni grupo baja de 5 en 2025/26, pero 5 grupos están ocultos por complementaria (Y3 C, Y9 D, Y10 C, Y10 D, Y11 C); al elegirlos, mensaje de la resta y el total del cuestionario como referencia.
- **Corregido: «Todavía no hay resultados» tras iniciar sesión como administrador** (26/10/2026). La web preguntaba qué había cargado antes de pedir el código; con la sesión sin verificar, el servidor devolvía una lista vacía sin error, y al pasar el código no volvía a preguntar. Los datos nunca estuvieron en peligro (recuento de la nube idéntico al del 22/10). Ahora la web no pide nada hasta que la sesión puede ver resultados y vuelve a preguntar al pasar el código; la pregunta la responde el servidor (`colectivos_cargados`, migración 26), que da error a quien no tiene acceso, y la pantalla distingue «no hay datos», «No tienes acceso a estos datos» y «No se han podido cargar los resultados».
- `supabase/scripts/preparar_local.sh`: recrea la base local con los datos reales y los usuarios de prueba (contraseñas en `datos_locales/usuarios_locales.txt`).
- Subido a la nube el 26/10/2026 (migraciones 24 a 26, 309 tests, recuento y validación idénticos antes y después; web desplegada con `f8c677b`).

## Sesión, caché y usuarios (rama `fase1-coordinacion`, 26/10/2026, pendiente de subir)

- **Navegador normal frente a incógnito.** La caché ya estaba bien (`index.html` sin caché, ficheros con huella con caché de un año); se amplía «sin caché» a todo lo que no lleva huella. La sesión guardada se valida con el servidor al abrir, antes de pedir datos: si no la reconoce, se borra y se vuelve al acceso; un fallo de red no la cierra. Mientras dura la validación se ignoran los avisos de Supabase, que al recuperar la sesión la emitía como iniciada y hacía pedir datos sin validar. La versión de la web (commit) se guarda con la sesión; si al abrir no coincide con la publicada, la sesión se renueva con el servidor. Un administrador sin doble factor va a pedir el código también al abrir con la sesión guardada, sin pedir ningún dato.
- **Usuarios, maquetación.** «Nuevo acceso» ya no se monta sobre la tabla ni la tapa: en pantallas anchas va al lado, con separación; por debajo de 1200 px, debajo. En móvil, cada usuario es una ficha y nada ensancha la página (comprobado a 1366, 1000 y 390 px).
- **Eliminar usuario** (migración 27, `admin_eliminar_usuario`): solo administración con doble factor; confirmación escribiendo el correo, también comprobada en el servidor; nadie se elimina a sí mismo ni al último administrador activo. Borra la cuenta y, en cascada, perfil, doble factor, sesiones y el código de una invitación pendiente. El registro de actividad conserva sus acciones pasadas con el nombre y el correo que tenía (columnas `usuario_nombre` y `usuario_correo`), y las que iban dirigidas a él ganan su correo en el detalle; la relación del registro con el usuario es «a nulo», nunca en cascada, y anota quién lo eliminó y cuándo. «Desactivar» se mantiene.
- 333 tests pgTAP (24 nuevos en `14_eliminar_usuario.sql`, incluido que no desaparece ninguna entrada y que el destinatario eliminado conserva nombre y correo) y 33 del frontend. Prueba de punta a punta en local con un navegador sin ventana: eliminar desde la pantalla, sesión revocada, versión distinta y doble factor al abrir.

## Paleta y retoques de textos (rama `paleta`, 26/10/2026)

- Paleta de gráficos, indicadores y alertas en `src/paleta.ts` (variables `--en-*` y PDF): escalas en tonos de positivo y negativo, del 1 a la izquierda al 6 a la derecha; recomendación; series; alertas con borde y fondo suave; cifras y etiquetas en todos los gráficos (especificación, «Paleta»).
- Pie de los PDF: «Colegio Internacional de Sevilla, San Francisco de Paula · Confidencial»; sin guiones como puntuación en la web ni en los PDF.
- Leyenda de los PDF: «menos de 5» y «oculto» en líneas separadas.
- Preguntas con la primera letra en mayúscula en la web, los PDF y los CSV (se aplica al recibir los datos; el texto guardado no cambia).
- Puntos fuertes y de mejora: número de orden junto a la pregunta. Tarjetas de Inicio: cifra y escala en una sola línea.

## Revisión de lenguaje de Aonia (rama `lenguaje-aonia`, 27/10/2026, desplegada)

- Términos inclusivos y uniformes (alumnado, profesorado, profesor/a, personal) en menús, títulos, filtros, leyendas, avisos, PDF, CSV y nombres de archivo; indicadores renombrados («Aspectos con mayor y menor valoración», «Aspectos más destacados», «Aspectos menos destacados»); recomendación en respuestas favorables, neutras y desfavorables. Glosario en `docs/GLOSARIO.md` y test `src/glosario.test.ts`.
- CSV con los enunciados exactamente como están guardados; mayúscula inicial solo en la web y los PDF.
- Tablas sin celdas partidas palabra a palabra: anchos de columna en los PDF según su contenido, rangos sin partir, anchos mínimos y filas apiladas en móvil.
- Propuestas aprobadas y aplicadas (27/10/2026): notas sin interpretaciones, jefaturas, persona responsable directa, rol «Administración», menú «Accesos», «Te damos la bienvenida», «Colegio» con mayúscula, «Mayor valoración» primero, rangos sin partir también en la web, plantilla Excel de asignación, mensajes del servidor (migración 20261027000028, que solo cambia textos, y Edge Function `admin-usuarios`), especificación, README y documentos de despliegue. 337 tests de base y 44 del frontend; validación de 2025/26 sin diferencias.
- Desplegada el 27/10/2026: copia previa de la nube, migración 20261027000028, función `admin-usuarios`, 337 tests en la nube, validación y recuento sin diferencias, web publicada desde `b743c86` (el commit `705998c` solo arregla un test).

## Protección de PDF y CSV y registro de descargas (rama `proteccion-descargas`, 27/10/2026, aprobada el 28/10/2026)

- Marca de agua en todas las páginas de todos los PDF, pie con «Descargado por… · Código…», propiedades (título, autor, asunto «Confidencial») y restricción de copia y edición (AES-256 con `@cantoo/pdf-lib` 2.11.1, dependencia nueva). CSV con «Confidencial · Uso exclusivo del Colegio», quién, cuándo y el código.
- Registro de descargas (migración 20261027000029): un código único por descarga y por cada informe de un ZIP, inalterable (trigger), pestaña «Descargas» en Accesos con filtros, búsqueda por código y exportación. Detalle en `docs/ESPECIFICACION.md` §7.7.
- 371 tests de base y 49 del frontend. Capturas en `datos_locales/capturas_descargas/`.
- Conservación del registro de descargas: dos años desde cada descarga y borrado después (aprobada el 28/10/2026; va en el encargo de tratamiento, `docs/DESPLIEGUE.md`). Pendiente: construir el borrado periódico (hoy el registro no deja borrar nada).
- Desplegada el 28/10/2026: copia previa `datos_locales/copias/nube_2026-10-28_0830` (comprobada), migración 20261027000029, 371 tests en la nube, validación y recuento sin diferencias, web publicada desde `f2dd38c`. Pendiente: que Rodrigo haga una descarga real en la web publicada y la busque por su código en Accesos › Descargas.

## Tareas con fecha

- **Eliminar las cuentas de demo y borrar `datos_locales/demo_accesos.txt`** (Rodrigo), el día de la demo, al terminar: fecha por confirmar. Son «Demo Dirección» (demo.direccion@demo.invalid) y «Demo Coordinación» (demo.coordinacion@demo.invalid), en producción y creadas con `datos_locales/scripts/crear_cuentas_demo.py`. Se eliminan en Accesos y el registro de actividad conserva su alta y su eliminación.
- Borrar las copias de la nube con la numeración antigua de migraciones: 02/11/2026.

## Bloqueos

- Cuestionario de personal en inglés (4 respuestas).
- Inglés de Y10 D: nombre y correo del docente que no está en Alexia (sustitución).
- Departamento o equipo en el fichero de personal: se verifica en el paso 3.
