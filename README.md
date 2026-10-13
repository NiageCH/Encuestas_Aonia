# Encuestas de satisfacción · CIS-SFP

Plataforma para consultar los resultados de las encuestas de satisfacción de alumnos, familias y personal del Colegio Internacional de Sevilla, San Francisco de Paula. Desarrolla Niage Technology para Aonia.

- Reglas y arquitectura: [`CLAUDE.md`](CLAUDE.md)
- Especificación completa: [`docs/ESPECIFICACION.md`](docs/ESPECIFICACION.md)
- Avance: [`docs/PROGRESO.md`](docs/PROGRESO.md)

## Estructura

```
src/            frontend (Vite + React + TypeScript); acceso a datos en src/data/
supabase/       migraciones, políticas RLS, funciones RPC y tests
etl/            carga de las exportaciones de Encuesta Fácil y plantillas Excel
docs/           especificación, progreso y manuales
referencia/     plantilla de la intranet y mockups (sin datos reales)
datos_locales/  fuera de git: fuentes, valores de validación y prototipo
```

## Datos y secretos

Nada de datos del colegio ni claves en el repositorio. Los ficheros de encuestas, los agregados reales y el prototipo viven en `datos_locales/` (ignorado por git). Las claves van en `.env`, a partir de `.env.example`.

Antes de cada push:

```sh
git ls-files | grep -E '^datos_locales/|\.env$|\.env\.|\.csv$|\.xlsx$' | grep -v '^\.env\.example$'
```

No debe devolver nada (salvo las plantillas vacías de `etl/plantillas/`).

## Requisitos

- Node 20 o superior.
- Docker Desktop arrancado (Supabase en local).
- Python 3.11 o superior (ETL, a partir del paso 3).

## Supabase en local

La CLI de Supabase está como dependencia de desarrollo (`npx supabase`). Los puertos son
los 554xx (API en `http://127.0.0.1:55421`, base de datos en `55422`, correo de prueba en
`http://127.0.0.1:55424`) para no chocar con otros proyectos Supabase en el mismo equipo.

```sh
npm install
npm run db:start     # arranca Supabase (la primera vez descarga las imágenes)
npm run db:reset     # recrea la base de datos aplicando las migraciones
npm run db:test      # tests pgTAP de supabase/tests
npm run db:stop
```

`npx supabase status` muestra las URL y las claves locales (no sirven fuera de tu equipo).

### Base de datos

- `supabase/migrations/`: modelo (§4), RLS, motor de anonimato y RPC.
- Las respuestas están en el esquema `privado`, que la API no expone y que además tiene
  RLS sin políticas. Desde el cliente solo se llama a las RPC de `public`:
  `resultados`, `resumen`, `detalle_preguntas`, `resultados_profesor` y `listar_profesores`.
- `supabase/tests/fixtures/datos_ejemplo.psql`: datos inventados para los tests.

### Probar el doble factor del administrador en local

El administrador solo obtiene resultados con una sesión verificada con TOTP (`aal2`).
Para comprobarlo de principio a fin contra la API local:

```sh
npm run db:reset
python3 supabase/scripts/probar_mfa_local.py
npm run db:reset     # borra el usuario de prueba
```

El script crea `admin.prueba@ejemplo.test`, entra con contraseña (las RPC responden 403
"Doble factor obligatorio"), da de alta un factor TOTP, calcula el código, lo verifica y
repite la consulta (responde 200).

Para hacerlo a mano con una app de autenticación:

1. Crea el usuario con la API de administración (clave `SERVICE_ROLE_KEY` de `npx supabase status`):
   `POST /auth/v1/admin/users` con `{"email": "...", "password": "...", "email_confirm": true}`.
2. Dale perfil de administrador en la base de datos:
   `insert into public.usuario_perfil (id, nombre, rol) values ('<id del usuario>', 'Admin', 'administrador');`
3. Entra con `POST /auth/v1/token?grant_type=password`: el token es `aal1`.
4. Alta del factor: `POST /auth/v1/factors` con `{"factor_type": "totp"}`. La respuesta trae
   `totp.qr_code` y `totp.secret`: escanéalo con la app.
5. `POST /auth/v1/factors/<id>/challenge` y después `POST /auth/v1/factors/<id>/verify` con
   `{"challenge_id": "...", "code": "<código de la app>"}`. El token nuevo es `aal2`.

En el frontend (paso 4) esto se hará con `supabase.auth.mfa.enroll`, `challenge` y `verify`.
