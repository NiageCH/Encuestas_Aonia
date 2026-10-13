# Progreso

Plan de trabajo en `docs/ESPECIFICACION.md` §9.

| Paso | Estado |
|---|---|
| 1. Repositorio, estructura, README, PROGRESO | Hecho |
| 2. Supabase local: migraciones, RLS, RPC, tests de anonimato | En curso |
| 3. ETL y validación | Bloqueado: faltan las exportaciones en `datos_locales/fuentes/` |
| 4 a 10 | Pendiente |

## Paso 1 · Repositorio (13/10/2026)

Hecho:
- Repositorio git en `main`, remoto `origin` en `NiageCH/Encuestas_Aonia` (privado).
- `.gitignore`: `datos_locales/`, `.env*` (salvo `.env.example`), `node_modules/`, `dist/`, temporales de Supabase y Python, y cualquier `.csv` o `.xlsx` fuera de `etl/plantillas/`.
- Estructura `src/data/`, `etl/plantillas/`, `supabase/`, `docs/`.
- README con la comprobación previa a cada push.

## Bloqueos

- `datos_locales/fuentes/` vacío (paso 3).
- Excel de profesores por asignatura y grupo, con departamento (paso 7 con datos reales).
- Departamento o equipo en el fichero de personal: se verifica en el paso 3.
