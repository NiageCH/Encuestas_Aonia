# Encuestas de satisfacción · CIS-SFP

Plataforma web para que el equipo directivo del Colegio Internacional de Sevilla, San Francisco de Paula, consulte los resultados de las encuestas de satisfacción de **alumnado, familias y personal**, con usuarios propios, permisos por rol e informes PDF por profesor/a y por responsable.

Desarrolla Niage Technology para Aonia. Repositorio privado.

| Documento | Para qué |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Reglas que no se rompen, arquitectura y comandos |
| [`docs/ESPECIFICACION.md`](docs/ESPECIFICACION.md) | Especificación completa de la Fase 1 |
| [`docs/PROGRESO.md`](docs/PROGRESO.md) | Qué está hecho, qué falta y qué está bloqueado |

---

## Estado

**Fase 1** (resultados del curso 2025/26). Las fases 2 (gestión y publicación de encuestas) y 3 (histórico y comparativa entre cursos) se construirán sobre el mismo modelo.

| Paso | Estado |
|---|---|
| 1. Repositorio y estructura | Hecho |
| 2. Supabase: modelo, RLS, RPC con anonimato, tests | Hecho; en la nube (Irlanda, UE) con las migraciones 1 a 23 y 289 tests en verde |
| 3. ETL de Encuesta Fácil y validación | Hecho; datos reales 2025/26 cargados en la nube y validados (falta el cuestionario de personal en inglés) |
| 4. Acceso, invitaciones y doble factor | Hecho |
| 5 y 6. Vistas y panel general, con exportación CSV y PDF de cada vista | Hecho |
| 7 y 8. Informes por persona: dirección, equipos, departamentos y profesorado (PDF y ZIP) | Hecho |
| 9. Accesos y registro de actividad | Hecho |
| 10. Despliegue | Entorno de pruebas en `encuestas-sfp.niage.eu`, en revisión interna. Pendiente: aceptación de Supabase por el colegio, dominio `encuestas.sfpaula.com`, plan Pro e invitaciones |

El detalle está en [`docs/PROGRESO.md`](docs/PROGRESO.md).

---

## Principios

1. **Anonimato según el rol** (criterio confirmado por Mark el (fecha pendiente), especificación §5.0). Para la coordinación y en el informe que recibe cada docente, ningún resultado agregado con menos de **5 respuestas**, con **supresión complementaria**: si en un reparto queda una sola parte oculta, se oculta también la siguiente más pequeña para que no se pueda deducir restando. Dirección y administración lo ven todo, con la marca «menos de 5». Se aplica en la base de datos, no en pantalla.
2. **Sin datos identificativos.** No se cargan IPs, identificadores de Encuesta Fácil, fechas de respuesta ni sexo. Las respuestas abiertas, tal cual, solo para Dirección y administración y sin enlace con las respuestas cerradas (§7.9).
3. **Las respuestas individuales nunca llegan al cliente.** Solo funciones (RPC) que aplican permisos y el criterio de cada rol; la única excepción son los textos de las respuestas abiertas, sueltos. Las exportaciones y los PDF salen de esas mismas funciones.
4. **Nada de datos del Colegio ni secretos en git.**
5. **Estilo de la intranet del Colegio** y textos en español, en un diccionario preparado para añadir inglés.

---

## Arquitectura

```
Navegador (Vite + React + TypeScript), servido por Clever Cloud (París) con Caddy
   │  src/data/: única capa que habla con el backend
   ▼
Supabase (Irlanda, UE)
   ├─ Auth: correo y contraseña, alta por invitación, TOTP obligatorio para las cuentas de administración
   ├─ public:   catálogo legible por usuarios activos + RPC de resultados
   ├─ permisos: funciones de rol usadas por las políticas RLS (no expuesto)
   └─ privado:  respuestas anónimas y motor de anonimato (no expuesto, RLS sin políticas)
   ▲
ETL en Python (etl/), ejecutada en local por Niage (conexión directa con DATABASE_URL)
   ▲
Exportaciones de Encuesta Fácil (SharePoint del Colegio → datos_locales/fuentes/)
```

Correo de Auth por SMTP de Brevo, configurado solo en el panel de Supabase (la clave nunca va al repositorio). Remitente provisional `encuestas@niage.eu`; previsto `encuestas@sfpaula.com`.

Entorno de pruebas: `https://encuestas-sfp.niage.eu`. Dirección prevista: `encuestas.sfpaula.com`. Detalle en [`docs/DESPLIEGUE.md`](docs/DESPLIEGUE.md).

---

## Estructura del repositorio

```
src/                frontend; acceso a datos en src/data/, PDF en src/pdf/, exportación en src/exportacion/
supabase/
  config.toml       configuración local (Auth, puertos 554xx) y de la nube ([remotes.pruebas])
  migrations/       modelo, RLS, motor de anonimato y RPC
  tests/            tests pgTAP y datos de ejemplo inventados (fixtures/)
  scripts/          utilidades locales (prueba del doble factor)
etl/                carga de Encuesta Fácil; plantillas Excel en etl/plantillas/
docs/               especificación, progreso y manuales
referencia/         plantilla de la intranet y mockups (sin datos reales)
datos_locales/      FUERA DE GIT: fuentes, valores de validación y prototipo
Caddyfile           servidor web del alojamiento: sirve dist/ con cabeceras de seguridad
```

---

## Puesta en marcha

### Requisitos

- Node 20 o superior.
- Docker Desktop arrancado.
- Python 3.11 o superior (ETL, a partir del paso 3).

### Supabase en local

La CLI de Supabase va como dependencia de desarrollo (`npx supabase`), con la versión fijada en `package-lock.json`.

```sh
npm install
npm run db:start     # arranca Supabase (la primera vez descarga las imágenes)
npm run db:reset     # recrea la base de datos aplicando las migraciones
npm run db:test      # tests pgTAP
npm test             # tests del frontend (navegación y CSV de exportación)
npm run db:stop
```

| Servicio | Dirección local |
|---|---|
| API (REST y Auth) | `http://127.0.0.1:55421` |
| Postgres | `127.0.0.1:55422` (usuario `postgres`) |
| Correo de prueba (Inbucket) | `http://127.0.0.1:55424` |

Los puertos son 554xx para no chocar con otros proyectos Supabase en el mismo equipo. `npx supabase status` muestra las URL y las claves locales, que solo sirven en tu equipo.

### Variables de entorno

Copia `.env.example` a `.env` y rellénalo. `.env` no va a git.

| Variable | Uso |
|---|---|
| `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` | Frontend |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | Scripts locales; nunca en el frontend |
| `DATABASE_URL` | ETL con `--remoto` (base de datos de la nube); sin `--remoto`, la ETL se niega a usar una dirección que no sea local |

En el alojamiento: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` y, cuando el colegio dé los resultados por buenos, `VITE_AVISO_VALIDACION=no` (quita la franja «Resultados en validación»). El SMTP de Brevo no va en ningún `.env`: solo en el panel de Supabase.

---

## Base de datos

### Modelo

| Grupo | Tablas |
|---|---|
| Catálogo por curso | `curso`, `cuestionario`, `bloque`, `grupo`, `asignatura`, `departamento`, `cargo`, `asignacion_docente` |
| Diccionario (estable entre cursos) | `pregunta` (con su escala), `opcion`, `pregunta_cuestionario`, `pregunta_comun` |
| Referencia | `colectivo`, `etapa`, `persona_responsable` |
| Respuestas (`privado`) | `respuesta` (grupo o etapa, idioma, docente, antigüedad, departamento o equipo), `respuesta_item` (valor o NS/NC), `respuesta_opcion` |
| Usuarios | `usuario_perfil` (rol y etapa), `registro_actividad` (solo escritura desde el servidor) |

Triggers de integridad: cada respuesta lleva lo que corresponde a su colectivo, los valores están dentro de la escala, la asignatura aparece si y solo si la pregunta es por asignatura, y un bloque no mezcla escalas.

### Roles

| | Administración | Dirección | Coordinación de etapa |
|---|---|---|---|
| Alumnado y familias | Todo | Todo | Solo su etapa |
| Personal | Todo | Todo | Sin acceso |
| Informes por persona | Todos los niveles | Todos los niveles | Solo Profesorado: el que da clase en su etapa, con los resultados de esa etapa |
| Exportar CSV y PDF | Inicio, Alumnado, Familias y Personal | Igual | Inicio, Alumnado y Familias (su etapa) |
| Accesos y registro | Sí | No | No |

La cuenta de administración solo accede con una sesión verificada con doble factor (`aal2`).

### RPC

Todas exigen un usuario con perfil activo, aplican los permisos de su rol y el anonimato, y devuelven valores **sin redondear** (el redondeo lo hace la vista).

| Función | Devuelve |
|---|---|
| `resultados(p_filtro, p_metrica, p_dimensiones)` | Total y partes de una métrica, con supresión |
| `resumen(p_filtro)` | Personas, satisfacción media y recomendación |
| `detalle_preguntas(p_filtro, p_bloque, p_dimensiones)` | Cada pregunta de un bloque, con distribución |
| `listar_profesores(p_curso)` | Profesorado con docencia visible para la cuenta |
| `resultados_profesor(p_curso, p_docente, p_metrica)` | Combinaciones asignatura y grupo, media global con las visibles y comparación con la etapa |
| `informe_profesor(p_curso, p_docente, p_lote)` | Informe completo de un profesor/a para el PDF (queda en el registro) |
| `informe_responsable`, `informe_jefe_departamento`, `informe_equipo` | Informes por persona: dirección, jefaturas de departamento y Equipo de Individuación |
| `listar_jefes`, `listar_equipo`, `media_departamento_alumnos` | Listas de responsables y media del profesorado de un departamento según el alumnado |
| `puntos_colectivo(p_filtro, p_cuantos)` | Aspectos con mayor y menor valoración de un colectivo |
| `comparacion_recomendacion(p_curso, p_colectivo)` | Media de cada bloque en las respuestas desfavorables y favorables a la recomendación |
| `registrar_exportacion(p_vista, p_formato, p_filtros)` | Deja una exportación CSV o PDF en el registro de actividad |
| `admin_usuarios`, `admin_actualizar_usuario`, `admin_registro` | Administración de accesos y registro de actividad (solo administración) |

**Filtro:** `curso` y `colectivo` obligatorios. Alumnado admite `cuestionario`, `etapa`, `grupo` y `asignatura`; familias, `etapa`; personal, **uno solo** de `docente`, `antiguedad` o `departamento_equipo`.

**Métricas:** `personas`, `satisfaccion`, `bloque` (con `codigo`), `pregunta` (con `codigo`), `recomendacion` (media, distribución y NPS) y `seleccion` (con `codigo`, para "aspectos más destacados").

**Dimensiones:** como máximo dos, por ejemplo `{grupo}` o `{grupo,asignatura}`.

Ejemplo con `supabase-js`:

```ts
const { data } = await supabase.rpc('resultados', {
  p_filtro: { curso: '2025/26', colectivo: 'alumnos', cuestionario: 'PAI_T' },
  p_metrica: { tipo: 'bloque', codigo: 'profesorado' },
  p_dimensiones: ['grupo'],
})
```

Respuesta (forma):

```json
{
  "total":  { "clave": {}, "suprimido": false, "n": 29, "media": 3.25, "n_valoraciones": 96, "ns_nc": 20 },
  "partes": [
    { "clave": { "grupo": "Y7 A" }, "suprimido": false, "n": 12, "media": 3.17 },
    { "clave": { "grupo": "Y7 C" }, "suprimido": true, "motivo": "menos_de_5" },
    { "clave": { "grupo": "Y7 D" }, "suprimido": true, "motivo": "complementaria" }
  ]
}
```

*(Datos inventados de la fixture de tests.)* Una parte suprimida no trae `n`, media ni distribución. Motivos: `menos_de_5`, `complementaria` y `sin_datos`.

### Cómo funciona el anonimato

- Un filtro que selecciona una parte de un total (un grupo, una asignatura, la etapa en familias, un segmento de personal) se calcula **dentro de su partición completa**. Así, una parte oculta por complementaria sigue oculta aunque se pida sola.
- La supresión complementaria se repite sobre filas, columnas y márgenes hasta que nada cambia (tabla asignatura por grupo).
- El mínimo se aplica también a cada pregunta: una pregunta con menos de 5 valoraciones válidas se oculta aunque el grupo sea visible.
- La media global de un profesor/a solo usa sus combinaciones visibles, y el informe indica cuántas se excluyen.

---

## Frontend en local

```sh
npm install
# .env.local con VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY (valores de `npx supabase status`)
python3 supabase/scripts/crear_usuario_local.py direccion@prueba.local UNA-CONTRASEÑA direccion
npm run dev          # http://127.0.0.1:5173
```

- Estilos: `src/estilos/intranet.css` son los bloques A y B de la plantilla, generados con `python3 scripts/extraer_plantilla.py` (no se editan a mano); los propios van en `src/estilos/encuestas.css` con el prefijo `en-`.
- Textos visibles: `src/i18n.ts` (`I18N.es`). Acceso a datos: solo `src/data/`.
- Supabase Studio en local: `http://127.0.0.1:55423`.
- Exportación de cada vista (`src/exportacion/`): un mismo modelo de tablas da el CSV (UTF-8 con BOM, punto y coma, coma decimal, para Excel en español) y el PDF. Celdas ocultas con «menos de 5» u «oculto», nunca en blanco. Archivos `Encuestas_2526_<Vista>[_<Filtro>].csv|pdf`.
- PDF (informes del profesor/a y de responsables): se generan en el navegador con `@react-pdf/renderer` (individual o en ZIP con `jszip`), cargados bajo demanda. Logos PNG y Raleway estática (con cifras de caja alta, como la web) salen de la plantilla con `.venv/bin/python scripts/generar_recursos_pdf.py`.

## Carga de datos (ETL)

Los ficheros de Encuesta Fácil van en `datos_locales/fuentes/` (fuera de git).

```sh
python3 -m venv .venv && .venv/bin/pip install -r etl/requirements.txt
.venv/bin/python etl/cargar_2526.py --ensayo   # convierte y resume, sin tocar la base de datos
.venv/bin/python etl/cargar_2526.py            # carga en la base de datos local (repetible)
.venv/bin/python etl/validar_2526.py           # compara con los agregados del prototipo (--remoto: la nube)
.venv/bin/python etl/borrar_2526.py            # recuento del curso; con --confirmar, lo borra (--remoto: la nube)
```

- Cada columna de cada fichero se carga o se descarta con un motivo; una columna sin regla detiene la carga.
- Nunca se cargan identificadores, fechas, IP, correo, nombres, sexo ni las preguntas cerradas del Plan de Igualdad. Las respuestas abiertas se cargan aparte, con `etl/cargar_abiertas_2526.py` (§7.9).
- El nombre del profesor/a o de la optativa que escribe el alumnado solo se usa en memoria para atribuir la respuesta a un docente; el texto nunca se carga. Del nivel de tutoría del personal solo se carga el tramo, y solo para el bloque del Equipo de Individuación.
- Informes de carga y de validación: `datos_locales/informes/`.

Asignación docente y responsables (orden de carga: encuestas, conversión, asignación y responsables):

```sh
.venv/bin/python etl/convertir_alexia_2526.py                         # listado de Alexia + revisión del Colegio → plantilla (datos_locales/)
.venv/bin/python etl/cargar_responsables.py                           # jefaturas de departamento y del Equipo de Individuación (datos_locales/)
.venv/bin/python etl/crear_plantilla_asignacion.py                    # plantilla para el Colegio (etl/plantillas/)
.venv/bin/python etl/cargar_asignaciones.py RUTA.xlsx --ensayo         # valida y lista lo que no casa
.venv/bin/python etl/cargar_asignaciones.py RUTA.xlsx                  # carga (sustituye las del curso)
.venv/bin/python etl/cargar_abiertas_2526.py --ensayo                  # respuestas abiertas: solo el recuento por pregunta, sin textos
.venv/bin/python etl/cargar_abiertas_2526.py                           # carga (después de cargar_2526.py, que las borra al recargar)
.venv/bin/python etl/ejemplo_asignaciones.py                          # docentes inventados para probar (datos_locales/)
```
- Para cargar en otra base de datos: `DATABASE_URL` en `.env` y `--remoto`. Una `DATABASE_URL` en el entorno tiene prioridad sobre `.env` (por ejemplo, la local: `DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:55422/postgres`).

## Tests

```sh
npm run db:test                         # base de datos local
npx supabase test db --linked           # la nube (los tests usan su propio curso inventado y no dejan nada)
npm test                                # frontend: navegación y CSV de exportación (vitest)
```

| Fichero | Qué comprueba |
|---|---|
| `01_acceso.sql` | Nadie lee `privado` ni escribe desde el cliente; perfiles activos; doble factor de la cuenta de administración |
| `02_anonimato.sql` | Mínimo de 5, complementaria, ataques por resta y por petición directa, tabla de dos dimensiones, filtros de personal |
| `03_calculos.sql` | Media agrupada, NS/NC, significado de n, distribución, NPS en escalas de 0 a 10 y de 1 a 10, aspectos más destacados |
| `04_profesor_y_roles.sql` | Vista del profesor/a y permisos de cada rol |
| `05_integridad.sql` | Reglas de carga que la ETL no puede saltarse |
| `06_etapas_y_departamentos.sql` | Familias con varias etapas, reuniones de departamento aisladas, respuestas del alumnado sin grupo |
| `07_administracion.sql` | Accesos, roles, desactivación y registro de actividad |
| `08_personal_informes.sql` | Lo que cada rol puede pedir en Informes por persona |
| `09_jefes_tramos_atribucion.sql` | Jefaturas de departamento, tramo de tutoría aislado de todo lo demás, partes ocultas juntas, clases propias, compartidas y atribuidas |
| `10_panel_mejora.sql` | Aspectos con mayor y menor valoración, comparación por recomendación aislada de cualquier otro filtro, mínimo de 5 y complementaria |
| `11_exportacion.sql` | Registro de cada exportación (vista, formato y filtros) y quién puede exportar qué |
| `12_coordinacion_e_ids.sql` | Identificador aleatorio de las respuestas; referencia del Colegio en Familias para la coordinación sin poder repartirla ni pedir otra etapa |
| `13_estado_vacio.sql` | «¿Hay resultados cargados?»: lista vacía solo si de verdad no hay; error (no «sin datos») para una cuenta de administración sin doble factor, un acceso desactivado o sin perfil |

Los datos de `supabase/tests/fixtures/datos_ejemplo.psql` son **inventados** y están diseñados para provocar cada caso.

### Doble factor de la cuenta de administración en local

```sh
npm run db:reset
python3 supabase/scripts/probar_mfa_local.py
npm run db:reset     # borra el usuario de prueba
```

El script crea `admin.prueba@ejemplo.test` y entra con contraseña: las RPC responden 403 ("Doble factor obligatorio"). Después da de alta un factor TOTP, lo verifica y repite la consulta, que responde 200.

Para probarlo a mano con una app de autenticación:

1. Crea el usuario con `POST /auth/v1/admin/users` y la `SERVICE_ROLE_KEY` local: `{"email": "...", "password": "...", "email_confirm": true}`.
2. Dale perfil: `insert into public.usuario_perfil (id, nombre, rol) values ('<id>', 'Admin', 'administrador');`
3. Entra con `POST /auth/v1/token?grant_type=password`: el token es `aal1`.
4. `POST /auth/v1/factors` con `{"factor_type": "totp"}` y escanea `totp.qr_code` con la app.
5. `POST /auth/v1/factors/<id>/challenge` y `POST /auth/v1/factors/<id>/verify` con el código: el token nuevo es `aal2`.

En la aplicación, una cuenta de administración que entra con contraseña ve la pantalla de doble factor: la primera vez, un QR para su aplicación de autenticación; después, el código de 6 cifras.

### Doble factor desactivado en local (solo desarrollo)

Para probar las pantallas de administración sin la aplicación de autenticación, la base de datos local puede tener el doble factor de las cuentas de administración desactivado. No está en ninguna migración: en producción sigue siendo obligatorio. Mientras está desactivado, la aplicación lo avisa en una franja. Los tests SQL lo activan siempre para comprobar la regla real.

```sh
# Desactivar (solo local)
docker exec supabase_db_encuestas-cis-sfp psql -U supabase_admin -d postgres -c "alter database postgres set app.mfa_admin_obligatorio = 'off'"
# Volver a activarlo
docker exec supabase_db_encuestas-cis-sfp psql -U supabase_admin -d postgres -c "alter database postgres reset app.mfa_admin_obligatorio"
# En los dos casos, reiniciar la API y las funciones
docker restart supabase_rest_encuestas-cis-sfp supabase_edge_runtime_encuestas-cis-sfp
```

### Invitaciones y usuarios en local

- Las invitaciones las envía la Edge Function `supabase/functions/admin-usuarios` (necesita la clave de servicio, que nunca llega al navegador). Supabase local la sirve sola al arrancar.
- Los correos (invitación y recuperación de contraseña, en español: `supabase/templates/`) llegan al buzón de pruebas: `http://127.0.0.1:55424`. En la nube, Brevo (configurado en el panel de Supabase).
- Prueba completa del circuito (invitación, correo, aceptar, contraseña, recuperar, permisos):

```sh
python3 supabase/scripts/probar_invitacion_local.py
```

Copia completa de la nube y prueba de restauración en una base local aparte (antes de cualquier cambio que toque datos de la nube):

```sh
.venv/bin/python supabase/scripts/copia_nube.py
```

---

## Datos y secretos

- Las exportaciones de Encuesta Fácil, los valores de validación y el prototipo con datos reales viven en `datos_locales/`, ignorado por git.
- `.gitignore` excluye también `.env*` (salvo `.env.example`) y cualquier `.csv` o `.xlsx` fuera de `etl/plantillas/`.

Antes de cada push, esta comprobación no debe devolver nada:

```sh
git ls-files | grep -iE '^datos_locales/|(^|/)\.env($|\.)|\.csv$|\.xlsx$' | grep -v '^\.env\.example$'
```

---

## Despliegue

Detalle en [`docs/DESPLIEGUE.md`](docs/DESPLIEGUE.md). Orden de cada subida:

1. GitHub, tras la comprobación de datos de arriba.
2. Migraciones en la nube: `npx supabase db push --dry-run` para ver qué se aplica y después `npx supabase db push`.
3. Tests en la nube (`npx supabase test db --linked`) con el recuento antes y después (`etl/borrar_2526.py --remoto`, sin `--confirmar`): debe ser idéntico.
4. Web: `npx clever-tools deploy` (sube el último commit; Clever compila y sirve con el `Caddyfile`).

## Forma de trabajo

- Commits pequeños, en español.
- Al cerrar cada paso del plan: actualizar `docs/PROGRESO.md`, pasar los tests, hacer la comprobación de datos y push.
- Toda la lógica de datos del frontend irá en `src/data/`: el colegio aún no ha confirmado si acepta Supabase o aporta su propio backend.

## Pendientes principales

- Revisión interna en la nube; después, invitar a las personas del Colegio.
- Decisión del Colegio sobre Supabase; plan Pro antes de las pruebas con el Colegio.
- Dominio `encuestas.sfpaula.com` y remitente `encuestas@sfpaula.com` (registros DNS del colegio).
- Cuestionario de personal en inglés (4 respuestas) y docente de Inglés de Y10 D.
- Confirmar las preguntas comunes del panel.
- Despliegue automático desde GitHub.
