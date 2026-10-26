# Plataforma de encuestas de satisfacción · CIS-SFP

Aplicación web para que el equipo directivo del Colegio Internacional de Sevilla – San Francisco de Paula consulte los resultados de las encuestas de satisfacción de alumnos, familias y personal, con usuarios propios, permisos por rol e informes PDF por profesor y por responsable. Desarrolla Niage Technology (Rodrigo) para Aonia.

**Fase actual: 1** (resultados 2025/26). Fase 2: gestión y publicación de encuestas. Fase 3: histórico. Diseña la Fase 1 para que las otras dos se construyan encima.

La especificación completa está en `docs/ESPECIFICACION.md`. Léela antes de empezar cada paso del plan.

## Reglas que no se rompen

1. **Mínimo de 5 respuestas** en todo resultado agregado, aplicado en el servidor, **con supresión complementaria** (ver especificación §5). Las combinaciones de filtros también lo cumplen.
2. **Sin datos identificativos:** no se cargan IPs, identificadores de Encuesta Fácil, fechas de respuesta, respuestas abiertas ni **sexo**.
3. **Las respuestas individuales nunca se leen desde el cliente.** Solo RPC agregadas (`security definer`), que aplican permisos, el mínimo de 5 y la supresión complementaria. Las exportaciones CSV y los PDF salen de esas mismas RPC.
4. **Nada de datos del colegio ni secretos en git.** Ni ficheros de encuestas, ni resultados agregados reales, ni claves. Todo eso vive en `datos_locales/` (ignorado) y en variables de entorno.
5. **Sin inicio de sesión con Microsoft.** Acceso con correo y contraseña. El correo puede salir por el servidor de correo del colegio (Microsoft 365). De SharePoint solo se leen ficheros.
6. **Estilo de la intranet CIS-SFP** (`referencia/plantilla-intranet-cis-sfp.html`): bloques A y B copiados tal cual, estilos propios con prefijo `en-`, solo los colores de `:root`, sin peticiones externas.
7. **Español por defecto**, con todos los textos visibles en un diccionario `I18N.es`.
8. **Textos sin guiones largos como puntuación.** Rangos con "a" ("de 1 a 6").

## Arquitectura

- GitHub privado (organización Niage) · Vite + React + TypeScript · alojamiento web en Clever Cloud (París), entorno de pruebas en `encuestas-sfp.niage.eu`, desplegado con `npx clever-tools deploy` (despliegue automático desde GitHub, pendiente).
- Supabase (Irlanda, UE; proyecto `osxjfmnhcyybgffanlqo`, plan Free hasta las pruebas con el colegio): Auth (correo y contraseña, alta por invitación, doble factor obligatorio para administradores), Postgres con RLS, RPC de agregación.
- Brevo como SMTP de Supabase Auth, configurado solo en el panel de Supabase (remitente provisional `encuestas@niage.eu`; previsto `encuestas@sfpaula.com`).
- ETL en Python (`etl/`), ejecutado en local por Niage con la clave de servicio de `.env`.
- Toda la lógica de datos del frontend en `src/data/`: el colegio aún no ha confirmado si acepta Supabase o pone su backend.

## Estructura del repositorio

```
src/          frontend (vistas, componentes, src/data/ para el acceso a datos)
supabase/     migraciones, políticas RLS, funciones RPC, tests
etl/          carga de Encuesta Fácil, diccionario, plantillas Excel
docs/         ESPECIFICACION.md, PROGRESO.md, manuales
referencia/   plantilla de la intranet y mockups (sin datos reales)
datos_locales/  NO va a git: fuentes, validación y prototipo con datos reales
```

## Comandos

```sh
npm install          # dependencias (incluye la CLI de Supabase)
npm run db:start     # Supabase local (Docker), puertos 554xx
npm run db:reset     # recrea la base de datos con las migraciones
bash supabase/scripts/preparar_local.sh   # base local desde cero con los datos reales de 2025/26 y usuarios de prueba
npm run db:test      # tests pgTAP (supabase/tests); en la nube: npx supabase test db --linked
npm test             # tests del frontend (vitest)
python3 supabase/scripts/probar_mfa_local.py   # prueba el doble factor del administrador
python3 supabase/scripts/probar_invitacion_local.py   # prueba invitaciones, contraseñas y permisos
.venv/bin/python etl/cargar_2526.py            # carga 2025/26 (--ensayo: sin tocar la base de datos)
.venv/bin/python etl/validar_2526.py           # validación contra el prototipo (--remoto: la nube)
.venv/bin/python etl/borrar_2526.py            # borra el curso 2025/26 (sin --confirmar solo muestra el recuento)
.venv/bin/python etl/convertir_alexia_2526.py      # listado de Alexia → plantilla de asignación (datos_locales/)
.venv/bin/python etl/cargar_asignaciones.py RUTA.xlsx  # asignación de profesores (plantilla en etl/plantillas/)
.venv/bin/python etl/cargar_responsables.py          # jefes de departamento y del Equipo de Individuación (datos_locales/)
npm run dev                                    # frontend en http://127.0.0.1:5173
python3 supabase/scripts/crear_usuario_local.py CORREO CLAVE direccion   # usuario de prueba local
python3 scripts/extraer_plantilla.py           # regenera los bloques A y B de la plantilla
.venv/bin/python scripts/generar_recursos_pdf.py   # logos PNG y Raleway TTF para los PDF
```

Despliegue: orden y comandos en README («Despliegue») y `docs/DESPLIEGUE.md`.

## Estado

Lleva el avance en `docs/PROGRESO.md`: qué está hecho, qué falta y qué está bloqueado. Actualízalo al terminar cada paso.

Bloqueos actuales (detalle en la especificación §10):
- Cuestionario de personal en inglés (4 respuestas): falta el fichero.
- Inglés de Y10 D: falta el docente que no está en Alexia (sustitución) para atribuirle sus valoraciones.
- Departamento o equipo en la encuesta de personal: no viene en 2025/26; se aplica el plan alternativo (§7.3).
