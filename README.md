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
