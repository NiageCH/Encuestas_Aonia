# Progreso

Plan de trabajo en `docs/ESPECIFICACION.md` §9.

| Paso | Estado |
|---|---|
| 1. Repositorio, estructura, README, PROGRESO | Hecho |
| 2. Supabase local: migraciones, RLS, RPC, tests de anonimato | Hecho (local; falta crear el proyecto en Frankfurt) |
| 3. ETL y validación | Hecho (validación completa en verde; falta el cuestionario de personal en inglés) |
| 4. Auth, perfiles, invitaciones, doble factor | Pendiente |
| 5. Diseño de la intranet y vistas por colectivo | En curso: alumnos, familias y personal hechas en local |
| 6. Panel general | Hecho en local (preguntas comunes candidatas, pendientes de confirmar) |
| 7 a 10 | Pendiente |

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
- Menú: Panel general · Alumnos · Familias · Personal (los informes por profesor irán dentro de Personal, §7.0). La coordinación no ve Personal.
- Alumnos: filtros de cuestionario y grupo, indicadores, profesorado por asignatura, bloques y recomendación.
- Familias: etapas (con la parte implícita «Sin etapa», §5.6), valoración general destacada y por etapa, bloques, detalle por pregunta, recomendación y lo más valorado.
- Personal: un filtro a la vez (docentes, no docentes, antigüedad), eNPS, dimensiones, Superiores (solo lo contestó el personal no docente), reuniones de departamento por departamento, Equipo de Individualización, detalle, recomendación, lo más valorado y dato de idioma.
- Información emergente en todos los gráficos, también con teclado.
- Migración 8: idioma como clave de partición de personal y `cuestionario.idiomas_cargados`.
- Tests: 142 en verde.

- Recomendación (§7.8): reparto como dato principal e «Índice de recomendación» como secundario, sin siglas.
- Idioma de personal: recuento informativo exacto (`recuento_idiomas`), fuera de la supresión (§5.11); no es filtro (migración 9).
- Panel general (paso 6): indicadores por colectivo, recomendación comparada con barras de reparto (alumnos en dos: Primaria y PAI con Bachillerato, migración 10), 26 preguntas comunes candidatas (`etl/preguntas_comunes_2526.py`) y lo más valorado comparado.

Pendiente del paso 5: vista de profesor (paso 7), revisión en móvil e iPad.

## Bloqueos

- Cuestionario de personal en inglés (4 respuestas).
- Excel de profesores por asignatura y grupo, con departamento (paso 7 con datos reales).
- Departamento o equipo en el fichero de personal: se verifica en el paso 3.
