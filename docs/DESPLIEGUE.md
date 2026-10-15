# Despliegue (paso 10)

Plan para pasar de Supabase local a producción. Nada de esto se ha ejecutado todavía: cada paso
en la nube lo autoriza Rodrigo antes de hacerlo.

## 0. Bloqueante previo

| Qué | Quién | Por qué |
|---|---|---|
| Confirmación de sistemas del colegio de que aceptan Supabase (§10, pregunta 4) | Rodrigo con sistemas | Su guía técnica dice que las herramientas con servidor, base de datos o usuarios las alojan ellos. Si no aceptan, el frontend no cambia (todo el acceso a datos está en `src/data/`), pero hay que rehacer el backend en su infraestructura. |
| Contratos de tratamiento de datos (RGPD) | Rodrigo (Niage) con el colegio y Aonia | Niage actúa como encargado del tratamiento. Supabase y Brevo tienen sus propios acuerdos de tratamiento (DPA) que hay que aceptar al crear las cuentas. |

## 1. Lo que necesito de Rodrigo

| # | Qué | Detalle | Dónde va |
|---|---|---|---|
| 1 | **Proyecto Supabase** en la región **Frankfurt (eu-central-1)**, en la organización de Niage | Recomendado el plan **Pro**: los proyectos gratuitos se pausan tras una semana sin uso y no tienen copias de seguridad diarias. | — |
| 2 | **Referencia del proyecto** (project ref) y **contraseña de la base de datos** | Para enlazar el repositorio (`supabase link`) y subir las migraciones. | Solo en el equipo de Rodrigo (`.env`, fuera de git) |
| 3 | Que Rodrigo ejecute `npx supabase login` en su equipo | La CLI necesita su token personal; no se comparte. | Su equipo |
| 4 | **Clave anon** y **URL** del proyecto | Son públicas por diseño (van en el frontend; la seguridad la dan RLS y las RPC). | Variables del alojamiento web |
| 5 | **Clave de servicio** (service_role) | Solo para la ETL en local. La Edge Function la recibe de Supabase sin que la tengamos que copiar. | `.env` local de Rodrigo, nunca en git ni en el alojamiento |
| 6 | **Cuenta de Brevo** (plan gratuito: 300 correos al día, suficiente) | Clave SMTP para Supabase Auth. | Panel de Supabase (SMTP) |
| 7 | **Remitente provisional de Niage** verificado en Brevo | Mientras el colegio no publique sus registros DNS (spec §3). | Brevo |
| 8 | **Alojamiento web** con región UE y despliegue automático desde GitHub | Decisión pendiente (ver abajo). Acceso a la cuenta o invitación al repositorio. | — |
| 9 | **Registros DNS del colegio** | `encuestas.sfpaula.com` (CNAME al alojamiento) y, para enviar desde `encuestas@sfpaula.com`, los que indique Brevo al dar de alta el dominio (código de verificación, DKIM y DMARC). | Sistemas del colegio |
| 10 | **Primer administrador** | El correo con el que entrará Rodrigo en producción; los demás se invitan desde la aplicación. | — |
| 11 | **Excel de asignación de profesores** y lista de jefes | Para que los informes de profesores y departamentos sean reales (sin él, se despliega sin asignaciones). | ETL |

### Alojamiento web: decisión pendiente

La aplicación es estática (HTML, CSS y JS): el alojamiento solo sirve ficheros; los datos van
del navegador a Supabase (Frankfurt) y nunca pasan por él. Aun así, la especificación pide región
UE y despliegue automático desde GitHub. Opciones a valorar:

- **Proveedor europeo** (por ejemplo, Clever Cloud o Scaleway): datos y empresa en la UE. Hay
  que comprobar que el despliegue automático desde GitHub y el certificado del dominio propio
  funcionan como esperamos.
- **Netlify, Vercel o Cloudflare Pages:** muy cómodos (GitHub, certificados y vistas previas),
  pero son empresas de EE. UU. con red de distribución mundial.

Recomendación: proveedor europeo, por coherencia con la guía del colegio. Decide Rodrigo.

## 2. Orden de trabajo

Cada paso se comprueba antes de pasar al siguiente.

1. **Supabase en la nube** (Rodrigo crea el proyecto; yo preparo y él ejecuta o autoriza):
   - `npx supabase link --project-ref <ref>`
   - `npx supabase db push` (las 14 migraciones)
   - `npx supabase functions deploy admin-usuarios`
   - `npx supabase secrets set SITIO_URL=<dirección provisional del alojamiento>`
   - Configuración de Auth igual que `supabase/config.toml`: alta libre desactivada, enlaces de
     24 horas, contraseñas de 10 caracteres con letras y números, TOTP activado, plantillas de
     correo en español (`supabase/templates/`), URL del sitio y de redirección.
   - Comprobar que el doble factor es obligatorio: `select public.mfa_admin_obligatorio()` debe devolver `true` (el interruptor `app.mfa_admin_obligatorio` solo existe en local).
   - Tests de la base de datos contra la nube: `npx supabase test db --linked` (corren en
     transacciones que se deshacen; no dejan datos).
2. **Carga de datos en la nube:** `DATABASE_URL` de producción en el `.env` local de Rodrigo,
   `etl/cargar_2526.py --remoto` y validación contra la nube (`etl/validar_2526.py`, con la misma
   opción). **No se cargan los docentes de ejemplo.**
3. **Correo:** Brevo con el remitente provisional de Niage → SMTP en Supabase Auth → prueba de
   invitación y de recuperación de contraseña a un correo de Rodrigo.
4. **Alojamiento web:** conectar el repositorio, variables `VITE_SUPABASE_URL` y
   `VITE_SUPABASE_ANON_KEY`, orden de compilación `npm ci && npm run build`, carpeta `dist`.
   Cabeceras de seguridad (política de contenidos que solo permita conexiones al proyecto de
   Supabase). Las rutas van tras «#», así que no hacen falta reglas de reescritura.
5. **Primer administrador:** alta de Rodrigo desde el panel de Supabase y su perfil de
   administrador con una sentencia SQL; al entrar, alta del doble factor. Desde ahí, invitaciones
   desde la aplicación.
6. **Dominio:** registro DNS de `encuestas.sfpaula.com` (sistemas del colegio) → certificado en el
   alojamiento → actualizar URL del sitio y de redirección en Auth y `SITIO_URL`.
7. **Remitente del colegio:** dominio `sfpaula.com` en Brevo con sus registros DNS → cambiar el
   remitente a `encuestas@sfpaula.com`.
8. **Pruebas finales:** móvil, iPad y escritorio; cada rol con un usuario real; PDF individuales y
   en lote; exportaciones.
9. **Documentación:** manual del administrador y guía de usuario de una página.
10. **Tarjeta en la intranet** del colegio que enlace a `encuestas.sfpaula.com`.

## 3. Lo que preparo antes, sin tocar la nube

- Opción `--remoto` en `etl/validar_2526.py` (hoy solo valida contra la base de datos local).
- Fichero de configuración del alojamiento elegido, con las cabeceras de seguridad.
- Guion SQL del primer administrador.
- Lista de comprobación de la configuración de Auth para compararla con el panel.
- Borradores del manual del administrador y de la guía de usuario.
