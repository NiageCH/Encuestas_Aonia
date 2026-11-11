# Guía para desarrolladores

Para quien vaya a cambiar la plataforma de encuestas de satisfacción del CIS-SFP: cómo montar el entorno, cómo está organizado el código y la base de datos, qué reglas no se pueden romper, qué comprobar antes de cada cambio y cómo desplegar.

La especificación completa está en [`ESPECIFICACION.md`](ESPECIFICACION.md): cada decisión del Colegio, con su fecha. El estado del trabajo, en [`PROGRESO.md`](PROGRESO.md). Esta guía no repite la especificación: dice dónde está cada cosa y cómo trabajar sin romperla.

---

## 1. Piezas

| Pieza | Tecnología | Dónde |
|---|---|---|
| Web | Vite, React y TypeScript, sin servidor propio: es una página estática | `src/` |
| Datos, permisos y anonimato | Supabase: Postgres con RLS y funciones RPC `security definer`, Auth y una Edge Function para el correo | `supabase/` |
| Carga de las encuestas | Python 3 (`psycopg`, `openpyxl`), ejecutado en local | `etl/` |
| PDF y CSV | En el navegador (`@react-pdf/renderer`, protegidos con `@cantoo/pdf-lib`) | `src/pdf/`, `src/exportacion/` |

Toda la lógica de anonimato está en la base de datos. La web nunca recibe respuestas individuales: solo resultados agregados, ya con el criterio del rol de quien los pide. Por eso casi cualquier cambio en lo que se enseña empieza por una migración y sus tests.

---

## 2. Montar el entorno local

### Requisitos

- Node 20 o superior.
- Docker Desktop arrancado (Supabase local va en contenedores).
- Python 3.9 o superior.

### Primera vez

```sh
npm install                                             # dependencias, también la CLI de Supabase (npx supabase)
python3 -m venv .venv && .venv/bin/pip install -r etl/requirements.txt
cp .env.example .env                                    # y rellenarlo: ver abajo
npm run db:start                                        # Supabase local, puertos 554xx
```

`npx supabase status` da las URL y las claves locales (solo valen en tu equipo). Van en `.env.local` para la web (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`) y en `.env` para los scripts. `.env` y `.env.local` nunca van a git.

| Servicio local | Dirección |
|---|---|
| API (REST y Auth) | `http://127.0.0.1:55421` |
| Postgres | `127.0.0.1:55422`, usuario `postgres`, contraseña `postgres` |
| Correo de prueba (Inbucket) | `http://127.0.0.1:55424` |

### Con los datos reales de 2025/26

Los ficheros del Colegio no están en el repositorio: se copian a mano en `datos_locales/`, que git ignora.

- `datos_locales/fuentes/`: las exportaciones de Encuesta Fácil (`2526_*.csv`, `Cliente_2526.xlsx`, `Empleado_2526.csv`) y el listado de Alexia (`Grupos_asignaturas_docentes_2025-26.xlsx`).
- `datos_locales/`: la revisión de departamentos del Colegio, la asignación convertida, los responsables (`responsables_2526.xlsx`) y los valores de control del prototipo.

Con eso, un solo comando deja la base local lista:

```sh
bash supabase/scripts/preparar_local.sh
```

Recrea la base con todas las migraciones, carga encuestas, asignación docente, responsables, respuestas abiertas, el catálogo de tutoría y servicios y los tutores, pasa la validación y la verificación de informes, crea cuatro usuarios de prueba (administración, Dirección y dos coordinaciones; contraseñas en `datos_locales/usuarios_locales.txt`) y desactiva el doble factor de administración, solo en local.

```sh
npm run dev                                             # http://127.0.0.1:5173
```

### Sin datos reales

Para tocar la lógica no hacen falta: los tests de la base de datos llevan sus propios datos inventados (`supabase/tests/fixtures/datos_ejemplo.psql`), pensados para provocar cada caso de anonimato. `npm run db:reset` deja la base vacía, con todas las migraciones.

---

## 3. Cómo está organizado el código

```
src/
  vistas/        una pantalla por fichero (Panel, Alumnos, Familias, Personal, Profesores, InformesPorPersona,
                 TutoriaServicios, Envio, InformeEnlace, Usuarios, Descargas, Abiertas...)
  componentes/   piezas compartidas: gráficos, tablas, «menos de 5» y «oculto», ayuda, detalle al pulsar
  data/          TODO el acceso a datos: una función por RPC y los modelos puros de las tablas (tablaProfesor.ts,
                 tablasResumen.ts). Nada fuera de src/data/ llama a Supabase
  pdf/           los PDF (informe del profesor/a, de nivel, de tutoría y servicios) y su protección
  exportacion/   CSV
  i18n.ts        todos los textos visibles (I18N.es)
  etiquetas.ts   textos que dependen de los datos (nombre de una clase, título de una jefatura...)
  navegacion.ts  rutas (#/...), parámetros de la dirección y qué ve cada rol
  glosario.ts    palabras que no se usan en la interfaz (el test glosario.test.ts las busca)
supabase/
  migrations/    el esquema y todas las funciones, en orden. Nunca se edita una migración ya aplicada en la nube
  tests/         pgTAP, uno por tema (01_acceso ... 35_tutoria_servicios_envio) y fixtures/ con datos inventados
  functions/     Edge Functions: admin-usuarios (altas) y enviar-informes (correo de los enlaces)
  scripts/       preparar_local.sh, usuarios de prueba, pruebas de doble factor e invitaciones
etl/
  *_2526.py      carga, validación y verificación del curso 2025/26; informes_2526.py dice qué preguntas van en los
                 informes de tutoría y de servicios
  cuenta_tecnica.py  la cuenta de Dirección temporal con la que la validación y la verificación piden resultados
docs/            especificación, progreso, despliegue, glosario, acceso con Microsoft, migración al servidor del Colegio
```

La lógica de datos de la web está toda en `src/data/` a propósito: si el Colegio pone su propio servidor en lugar de Supabase, solo cambia esa carpeta.

---

## 4. La base de datos

### Esquemas

| Esquema | Qué guarda | Quién lo lee |
|---|---|---|
| `public` | Cursos, cuestionarios, bloques, preguntas, grupos, asignaturas, departamentos, personas responsables, cargos, tutoría, servicios, perfiles y registro de actividad | Lectura de lo que no son respuestas, con RLS por rol. Nadie escribe desde la web: todo pasa por RPC |
| `privado` | Las respuestas (`respuesta`, `respuesta_item`, `respuesta_opcion`, `respuesta_etapa`), su atribución a docentes y tramos, las respuestas abiertas, los enlaces y su configuración, y las funciones internas | Nadie desde la web. Solo las funciones `security definer` |
| `permisos` | Quién es quien llama (`permisos.perfil()`, `permisos.exigir()`, `permisos.ve_todo()`) | Las funciones |

### La única puerta: las RPC

La web solo llama a funciones `public.*` (por ejemplo `public.resultados`, `public.informe_profesor`, `public.informe_tutoria`). Cada una:

1. es `security definer` con `set search_path = ''` (todos los nombres con su esquema);
2. empieza comprobando quién llama (`permisos.exigir()`, `permisos.ve_todo()` o `privado.exigir_admin()`);
3. calcula con las funciones de `privado`, que ya aplican el anonimato del rol;
4. termina con `revoke execute ... from public, anon` y `grant execute ... to authenticated`. Las de `privado` se quedan sin `grant` para nadie.

### Cómo se aplica el anonimato

- `privado.ve_menos_de_5()`: el único sitio que decide el criterio. Verdadero solo para Dirección y administración, y nunca cuando la transacción pide la versión del destinatario (`encuestas.version_docente = 'on'`). Ese ajuste solo endurece: sin el rol de Dirección no ablanda nada.
- `privado.celdas(cuestionarios, dimensiones, métrica)`: cuenta y promedia desde las respuestas (n, valoraciones, NS/NC, media, reparto).
- `privado.celdas_suprimidas(...)`: aplica el mínimo de 5 y la supresión complementaria a la vez en todas las tablas que se pueden comparar (bloque con sus preguntas, satisfacción general con sus bloques, cada margen con sus celdas). La regla, en `privado.suprimir_relacionada`: en ninguna relación puede quedar oculto un solo miembro.
- `privado.fila(...)`: lo que sale hacia la web. Oculto, sin cifra, con su motivo (`menos_de_5`, `complementaria`); visible con menos de 5, solo para Dirección y administración, con la marca `menos_de_5`.
- `public.resultados(filtro, métrica, dimensiones)`: la entrada general, que pasa por `privado.resolver` (qué cuestionarios y qué filtros puede pedir cada rol) y por todo lo anterior. **Un informe nuevo debería construirse sobre `public.resultados`**: así cada celda es la misma que la coordinación ve en la pantalla correspondiente, con la misma supresión. Es lo que hacen los informes de tutoría y de servicios (migración 49).

### Versiones de los informes

Cada informe con nombre tiene dos versiones: la **completa** (Dirección y administración, con lo de menos de 5 marcado) y la **del destinatario** (docente, jefatura, tutor/a o responsable del servicio: mínimo de 5 y complementaria). La función pública recibe `p_version`, pone `encuestas.version_docente = 'on'` mientras calcula y lo deja como estaba. El enlace personal (`public.informe_enlace`) siempre fuerza la del destinatario.

---

## 5. Reglas que no se pueden romper

Están en `CLAUDE.md` y en la especificación (§5 y §6). En la práctica:

1. **Mínimo de 5 según el rol.** Coordinación y destinatarios de informes: ningún resultado de menos de 5 respuestas, con supresión complementaria. Dirección y administración: todo, con la marca «menos de 5». Siempre en el servidor, nunca filtrando en la web.
2. **Supresión complementaria.** Si en un total con sus partes queda oculta una sola parte, se oculta otra (la visible más pequeña), también entre tablas relacionadas. Cualquier función nueva que enseñe un total y sus partes tiene que pasar por `privado.celdas_suprimidas` (o por `public.resultados`), no calcular su propia suma.
3. **Permisos por rol** (tabla de la especificación §6). La coordinación solo su etapa y nunca personal, respuestas abiertas ni informes de responsables; el envío y los accesos, solo administración. La web esconde lo que un rol no puede ver, pero quien decide es el servidor: cada RPC lo comprueba.
4. **Nada de respuestas individuales hacia la web.** Ninguna política RLS permite leer `privado`. Única excepción: los textos sueltos de las respuestas abiertas, solo para Dirección y administración.
5. **Sin datos identificativos**: no se cargan IP, identificadores de Encuesta Fácil, fechas de respuesta ni sexo.
6. **Nada del Colegio en git**: ni ficheros de encuestas, ni resultados reales (tampoco en tests, documentos o mensajes de commit: los tests usan cifras inventadas), ni claves. Todo eso vive en `datos_locales/` y en variables de entorno.
7. **Textos**: todos en `src/i18n.ts`, en español, sin guiones largos como puntuación y respetando el glosario (`docs/GLOSARIO.md`; el test `src/glosario.test.ts` falla si no).
8. **Estilo de la intranet**: bloques A y B de la plantilla tal cual, estilos propios con prefijo `en-`, sin peticiones externas, colores de `src/paleta.ts`.

---

## 6. Antes de cada cambio

En una rama desde `main`. Al terminar, todo esto en verde:

```sh
npx tsc --noEmit -p .          # tipos
npm test                       # web (vitest): navegación, tablas, CSV, glosario, paleta...
npm run db:test                # base de datos (pgTAP), con la base local recién migrada
```

Si el cambio toca la base de datos, una migración nueva en `supabase/migrations/` (fecha y número siguiente, por ejemplo `20261111000049_...sql`) y su test en `supabase/tests/`, que intente saltarse la regla: pedir lo de otro rol, despejar una celda oculta restando, abrir un informe ajeno con un enlace. `npx supabase migration up --local` aplica las migraciones nuevas sin borrar los datos; `bash supabase/scripts/preparar_local.sh` lo rehace todo desde cero.

**Si el cambio toca los informes** (profesorado, jefaturas, Equipo de Individuación, tutoría, servicios, sus funciones o sus tablas en la web), **y después de cada carga de datos**:

```sh
.venv/bin/python etl/verificar_informes_2526.py
```

Recalcula desde las respuestas, sin funciones de la plataforma, cada cifra de cada informe en las dos versiones y comprueba el motivo de cada celda oculta. Tiene que dar **0 diferencias**. El resultado (solo cifras) queda en `datos_locales/informes/`. Si añades un informe nuevo, añádelo también a este script.

Si el cambio toca la carga o los cálculos generales: `.venv/bin/python etl/validar_2526.py` (comparación con los valores de control del prototipo; las diferencias esperadas están explicadas en `docs/PROGRESO.md`).

Antes de subir a GitHub, esta comprobación no debe devolver nada:

```sh
git ls-files | grep -iE '^datos_locales/|(^|/)\.env($|\.)|\.csv$|\.xlsx$' | grep -v '^\.env\.example$'
```

Y la **prueba a mano** de `docs/DESPLIEGUE.md` §9: con Dirección, administración y una coordinación, cambiar a mano cada desplegable y cada filtro de cada pantalla, sin errores en la consola. Los tests no la sustituyen: el 03/11/2026 un desplegable que los tests daban por bueno no se podía cambiar en la web publicada.

---

## 7. Cómo desplegar

Orden de cada subida (detalle y valores en `docs/DESPLIEGUE.md`):

1. **GitHub**: `main` y la rama, tras la comprobación de datos.
2. **Migraciones en la nube**: `npx supabase db push --dry-run` para ver qué se aplica y después `npx supabase db push`.
3. **Tests en la nube**: `npx supabase test db --linked`, con el recuento antes y después (`.venv/bin/python etl/borrar_2526.py --remoto`, sin `--confirmar`: solo cuenta) idéntico. Los tests usan su propio curso inventado y no dejan nada. La CLI entra con una contraseña temporal que dura unos 5 minutos: si la nube va lenta, pasar los tests en tandas de pocos ficheros.
4. **Verificación en la nube**, si la subida toca los informes: `etl/verificar_informes_2526.py --remoto`, con 0 diferencias.
5. **Web**: `npx clever-tools deploy` (sube el último commit; Clever Cloud compila y sirve con el `Caddyfile`).
6. **Prueba a mano en la web publicada** (§9), con los tres roles.

Secretos: el correo (SMTP) y la configuración de Auth están en el panel de Supabase; las variables de la web (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`) en Clever Cloud; los de la Edge Function `enviar-informes`, como secretos de la función. Ninguno en el repositorio. El envío real de correos al Colegio tiene doble cerrojo: `privado.configuracion_envio.modo` en la base de datos y `ENVIO_PROFESORADO=activo` con el remitente del Colegio en la función.

Cuando la plataforma pase al entorno del Colegio, el plan está en [`MIGRACION_SERVIDOR_COLEGIO.md`](MIGRACION_SERVIDOR_COLEGIO.md); el acceso con Microsoft, en [`MICROSOFT_SISTEMAS.md`](MICROSOFT_SISTEMAS.md) y la especificación §7.11.

---

## 8. Cambios habituales

- **Un texto**: en `src/i18n.ts`. Si es nuevo, que el glosario lo acepte (`npm test`).
- **Una pantalla o un filtro**: la vista en `src/vistas/`, sus datos en `src/data/` y, si lleva parámetros en la dirección, `PARAMETROS` en `src/navegacion.ts` (y su test).
- **Un informe nuevo**: una función `privado.informe_x` sobre `public.resultados`, una pública `public.informe_x(p_curso, ..., p_registrar, p_version)` que comprueba el rol y la versión, el enlace (`informe_enlace`, `descarga_enlace`, `privado.destinatarios` si se envía), el test pgTAP, la tabla en `src/data/` (pura, con su test), la pantalla, el PDF y la verificación independiente. Los informes de tutoría y de servicios (migración 49, `src/data/tablasResumen.ts`, `src/vistas/TutoriaServicios.tsx`, `src/pdf/InformeResumenPdf.tsx`) son el ejemplo más reciente y completo.
- **Un curso nuevo**: los scripts `*_2526.py` son de 2025/26 (las preguntas, sus códigos y las equivalencias cambian de un curso a otro). Se copian y se ajustan; la Fase 2 de la especificación prevé gestionar las encuestas desde la propia plataforma.
- **Qué preguntas van en tutoría y en servicios**: `etl/informes_2526.py` y `etl/cargar_informes_2526.py`. Los responsables de servicio los mantiene administración desde la aplicación (Informes por persona › Servicios); los tutores, `etl/cargar_tutores_2526.py` desde la hoja de Alexia.

Commits pequeños, en español. Al cerrar un paso, `docs/PROGRESO.md` al día.
