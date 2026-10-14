# Encuestas de satisfacción · CIS-SFP

Plataforma web para que el equipo directivo del Colegio Internacional de Sevilla, San Francisco de Paula, consulte los resultados de las encuestas de satisfacción de **alumnos, familias y personal**, con usuarios propios, permisos por rol e informes PDF por profesor y por responsable.

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
| 2. Supabase: modelo, RLS, RPC con anonimato, tests | Hecho en local; falta el proyecto en la nube (Frankfurt) |
| 3. ETL de Encuesta Fácil y validación | Hecho (falta el cuestionario de personal en inglés) |
| 4 a 10. Auth, vistas, panel, informes PDF, administración, despliegue | Pendiente |

El detalle está en [`docs/PROGRESO.md`](docs/PROGRESO.md).

---

## Principios

1. **Anonimato.** Ningún resultado agregado con menos de **5 respuestas**, con **supresión complementaria**: si en un reparto queda una sola parte oculta, se oculta también la siguiente más pequeña para que no se pueda deducir restando. Se aplica en la base de datos, no en pantalla.
2. **Sin datos identificativos.** No se cargan IPs, identificadores de Encuesta Fácil, fechas de respuesta, respuestas abiertas ni sexo.
3. **Las respuestas individuales nunca llegan al cliente.** Solo funciones agregadas (RPC) que aplican permisos y anonimato. Las exportaciones y los PDF salen de esas mismas funciones.
4. **Nada de datos del colegio ni secretos en git.**
5. **Estilo de la intranet del colegio** y textos en español, en un diccionario preparado para añadir inglés.

---

## Arquitectura

```
Navegador (Vite + React + TypeScript)        ← pendiente (paso 5)
   │  src/data/: única capa que habla con el backend
   ▼
Supabase (Frankfurt)
   ├─ Auth: correo y contraseña, alta por invitación, TOTP obligatorio para administradores
   ├─ public:   catálogo legible por usuarios activos + RPC de resultados
   ├─ permisos: funciones de rol usadas por las políticas RLS (no expuesto)
   └─ privado:  respuestas anónimas y motor de anonimato (no expuesto, RLS sin políticas)
   ▲
ETL en Python (etl/), ejecutada en local por Niage con la clave de servicio   ← paso 3
   ▲
Exportaciones de Encuesta Fácil (SharePoint del colegio → datos_locales/fuentes/)
```

Correo de Auth por SMTP de Brevo. Dirección prevista: `encuestas.sfpaula.com`.

---

## Estructura del repositorio

```
src/                frontend; acceso a datos en src/data/
supabase/
  config.toml       configuración local (Auth, puertos 554xx)
  migrations/       modelo, RLS, motor de anonimato y RPC
  tests/            tests pgTAP y datos de ejemplo inventados (fixtures/)
  scripts/          utilidades locales (prueba del doble factor)
etl/                carga de Encuesta Fácil; plantillas Excel en etl/plantillas/
docs/               especificación, progreso y manuales
referencia/         plantilla de la intranet y mockups (sin datos reales)
datos_locales/      FUERA DE GIT: fuentes, valores de validación y prototipo
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
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | ETL, solo en local; nunca en el frontend |
| `BREVO_SMTP_USER`, `BREVO_SMTP_PASSWORD` | SMTP de Supabase Auth |

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

| | Administrador | Dirección | Coordinación de etapa |
|---|---|---|---|
| Alumnos y familias | Todo | Todo | Solo su etapa |
| Personal | Todo | Todo | Sin acceso |
| Profesores | Todos | Todos | Los que dan clase en su etapa, con los resultados de esa etapa |
| Usuarios y registro | Sí | No | No |

El administrador solo accede con una sesión verificada con doble factor (`aal2`).

### RPC

Todas exigen un usuario con perfil activo, aplican los permisos de su rol y el anonimato, y devuelven valores **sin redondear** (el redondeo lo hace la vista).

| Función | Devuelve |
|---|---|
| `resultados(p_filtro, p_metrica, p_dimensiones)` | Total y partes de una métrica, con supresión |
| `resumen(p_filtro)` | Personas, satisfacción media y recomendación |
| `detalle_preguntas(p_filtro, p_bloque, p_dimensiones)` | Cada pregunta de un bloque, con distribución |
| `listar_profesores(p_curso)` | Profesores con docencia visibles para el usuario |
| `resultados_profesor(p_curso, p_docente, p_metrica)` | Combinaciones asignatura y grupo, media global con las visibles y comparación con la etapa |

**Filtro:** `curso` y `colectivo` obligatorios. Alumnos admite `cuestionario`, `etapa`, `grupo` y `asignatura`; familias, `etapa`; personal, **uno solo** de `docente`, `antiguedad` o `departamento_equipo`.

**Métricas:** `personas`, `satisfaccion`, `bloque` (con `codigo`), `pregunta` (con `codigo`), `recomendacion` (media, distribución y NPS) y `seleccion` (con `codigo`, para "lo más valorado").

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
- La media global de un profesor solo usa sus combinaciones visibles, y el informe indica cuántas se excluyen.

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
- PDF (informes de profesor): se generan en el navegador con `@react-pdf/renderer` (individual o en ZIP con `jszip`), cargados bajo demanda. Logos PNG y Raleway estática (con cifras de caja alta, como la web) salen de la plantilla con `.venv/bin/python scripts/generar_recursos_pdf.py`.

## Carga de datos (ETL)

Los ficheros de Encuesta Fácil van en `datos_locales/fuentes/` (fuera de git).

```sh
python3 -m venv .venv && .venv/bin/pip install -r etl/requirements.txt
.venv/bin/python etl/cargar_2526.py --ensayo   # convierte y resume, sin tocar la base de datos
.venv/bin/python etl/cargar_2526.py            # carga en la base de datos local (repetible)
.venv/bin/python etl/validar_2526.py           # compara con los agregados del prototipo
```

- Cada columna de cada fichero se carga o se descarta con un motivo; una columna sin regla detiene la carga.
- Nunca se cargan identificadores, fechas, IP, correo, nombres, respuestas abiertas, sexo ni el Plan de Igualdad.
- Informes de carga y de validación: `datos_locales/informes/`.

Asignación de profesores (Excel del colegio):

```sh
.venv/bin/python etl/crear_plantilla_asignacion.py                    # plantilla para el colegio (etl/plantillas/)
.venv/bin/python etl/cargar_asignaciones.py RUTA.xlsx --ensayo         # valida y lista lo que no casa
.venv/bin/python etl/cargar_asignaciones.py RUTA.xlsx                  # carga (sustituye las del curso)
.venv/bin/python etl/ejemplo_asignaciones.py                          # docentes inventados para probar (datos_locales/)
```
- Para cargar en otra base de datos: `DATABASE_URL` en `.env` y `--remoto`.

## Tests

```sh
npm run db:test
```

| Fichero | Qué comprueba |
|---|---|
| `01_acceso.sql` | Nadie lee `privado` ni escribe desde el cliente; perfiles activos; doble factor del administrador |
| `02_anonimato.sql` | Mínimo de 5, complementaria, ataques por resta y por petición directa, tabla de dos dimensiones, filtros de personal |
| `03_calculos.sql` | Media agrupada, NS/NC, significado de n, distribución, NPS en escalas de 0 a 10 y de 1 a 10, lo más valorado |
| `04_profesor_y_roles.sql` | Vista de profesor y permisos de cada rol |
| `05_integridad.sql` | Reglas de carga que la ETL no puede saltarse |

Los datos de `supabase/tests/fixtures/datos_ejemplo.psql` son **inventados** y están diseñados para provocar cada caso.

### Doble factor del administrador en local

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

En la aplicación, un administrador que entra con contraseña ve la pantalla de doble factor: la primera vez, un QR para su aplicación de autenticación; después, el código de 6 cifras.

### Invitaciones y usuarios en local

- Las invitaciones las envía la Edge Function `supabase/functions/admin-usuarios` (necesita la clave de servicio, que nunca llega al navegador). Supabase local la sirve sola al arrancar.
- Los correos (invitación y recuperación de contraseña, en español: `supabase/templates/`) llegan al buzón de pruebas: `http://127.0.0.1:55424`. Brevo se configura en el despliegue.
- Prueba completa del circuito (invitación, correo, aceptar, contraseña, recuperar, permisos):

```sh
python3 supabase/scripts/probar_invitacion_local.py
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

## Forma de trabajo

- Commits pequeños, en español.
- Al cerrar cada paso del plan: actualizar `docs/PROGRESO.md`, pasar los tests, hacer la comprobación de datos y push.
- Toda la lógica de datos del frontend irá en `src/data/`: el colegio aún no ha confirmado si acepta Supabase o aporta su propio backend.

## Pendientes principales

- Exportaciones 2025/26 en `datos_locales/fuentes/` (paso 3).
- Excel de profesores por asignatura y grupo, con departamento (vista de profesor con datos reales).
- Saber si el fichero de personal trae departamento o equipo (informes de responsables).
- Decisión del colegio sobre Supabase y registros DNS del dominio y del remitente.
