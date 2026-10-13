# Progreso

Plan de trabajo en `docs/ESPECIFICACION.md` §9.

| Paso | Estado |
|---|---|
| 1. Repositorio, estructura, README, PROGRESO | Hecho |
| 2. Supabase local: migraciones, RLS, RPC, tests de anonimato | Hecho (local; falta crear el proyecto en Frankfurt) |
| 3. ETL y validación | Bloqueado: faltan las exportaciones en `datos_locales/fuentes/` |
| 4 a 10 | Pendiente |

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
- Crear el proyecto en la nube (Frankfurt) y enlazarlo (`supabase link`). Esperando la decisión del colegio sobre Supabase.
- RPC de exportación CSV con registro de actividad (se hará con las vistas, pasos 5 y 6).
- `ultimo_acceso` y aviso de 90 días (paso 4).
- Forma de carga de la ETL: conexión directa a Postgres o RPC de carga solo para `service_role` (paso 3).

Notas técnicas:
- En `config.toml`, `[auth.email] enable_signup` debe quedar en `true`: en `false` desactiva también el login con correo. El alta libre se bloquea con `[auth] enable_signup = false`.

## Bloqueos

- `datos_locales/fuentes/` vacío (paso 3).
- Excel de profesores por asignatura y grupo, con departamento (paso 7 con datos reales).
- Departamento o equipo en el fichero de personal: se verifica en el paso 3.
