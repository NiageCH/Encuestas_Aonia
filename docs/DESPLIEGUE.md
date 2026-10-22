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
| 1 | **Proyecto Supabase** en la región **Irlanda, UE (eu-west-1)**, en la organización de Niage. **Creado el 22/10/2026** (`osxjfmnhcyybgffanlqo`, plan Free) | Pasar al plan **Pro** antes de las pruebas con el colegio: los proyectos gratuitos se pausan tras una semana sin uso y no tienen copias de seguridad diarias. | — |
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
del navegador a Supabase (Irlanda, UE) y nunca pasan por él. Aun así, la especificación pide región
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

## 4. Entorno de pruebas: encuestas-sfp.niage.eu (22/10/2026)

Hasta que el colegio tenga `encuestas.sfpaula.com`, las pruebas van en un subdominio de Niage.
Supabase: proyecto `osxjfmnhcyybgffanlqo` (Irlanda, UE, plan Free), sin datos reales.

### Alojamiento: Clever Cloud (empresa francesa, región París)

1. Crear una aplicación **Static** en la región **Paris (par)**, tamaño mínimo (nano).
2. Despliegue desde el equipo de Rodrigo con clever-tools (Clever pide acceso OAuth a todos los
   repositorios de NiageCH, y no se autoriza). Aplicación `Encuestas-SFP`, enlazada con
   `npx clever-tools link` (el enlace, `.clever.json`, no va a git). Para publicar una versión:
   primero `git push origin main`, para que GitHub y Clever tengan la misma, y después
   `npx clever-tools deploy` (sube el último commit; Clever compila y sirve). Estado y registro:
   `npx clever-tools status` y `npx clever-tools logs`.
   **Despliegue automático (más adelante):** acción de GitHub con las claves de un usuario de
   Clever exclusivo para despliegues, miembro solo de una organización de Clever que contenga
   únicamente esta aplicación, y secretos en un entorno protegido de GitHub del repositorio
   Encuestas_Aonia limitado a `main`. Las claves de Clever tienen los permisos de su usuario, no
   de una aplicación: de ahí el usuario y la organización exclusivos.
3. Variables de entorno de la aplicación:

   | Variable | Valor |
   |---|---|
   | `CC_BUILD_COMMAND` | `npm ci --ignore-scripts && npm run build` |
   | `VITE_SUPABASE_URL` | `https://osxjfmnhcyybgffanlqo.supabase.co` |
   | `VITE_SUPABASE_ANON_KEY` | clave pública *anon* (Project Settings → API). Es pública por diseño. |

   `--ignore-scripts` evita descargar la CLI de Supabase en cada compilación. No se pone
   `CC_WEBROOT`: el `Caddyfile` de la raíz sirve `dist/` con las cabeceras de seguridad (política
   de contenidos que solo permite conectar con el propio origen y con `VITE_SUPABASE_URL`, HSTS,
   sin marcos, sin rastreo de origen). Probado en local con Caddy 2.11.
4. Dominio: añadir `encuestas-sfp.niage.eu` en la aplicación (Domain names) y activar «Force
   HTTPS». Clever Cloud genera el certificado de Let's Encrypt solo, durante los 3 días
   siguientes a añadir el dominio.

### DNS en niage.eu (GoDaddy, servidores ns41/ns42.domaincontrol.com)

| Tipo | Nombre | Valor | TTL |
|---|---|---|---|
| CNAME | `encuestas-sfp` | `domain.par.clever-cloud.com.` | 1 hora |

### Valores de la nube

- Secreto de la función de invitaciones: `SITIO_URL=https://encuestas-sfp.niage.eu`
  (`npx supabase secrets set SITIO_URL=https://encuestas-sfp.niage.eu`).
- Auth → URL Configuration: Site URL `https://encuestas-sfp.niage.eu`; Redirect URLs solo
  `https://encuestas-sfp.niage.eu/**` (sin `127.0.0.1` ni `localhost`, que quedan solo en el
  `config.toml` local).

### Correo de pruebas: Brevo con remitente encuestas@niage.eu

1. Cuenta de Brevo (plan gratuito, 300 correos al día). Senders, Domains & Dedicated IPs →
   Domains → añadir `niage.eu` y autenticarlo de forma manual.
2. Registros DNS en niage.eu (los valores exactos de la verificación y de DKIM los da Brevo al
   añadir el dominio):

   | Tipo | Nombre | Valor |
   |---|---|---|
   | TXT | `@` | `brevo-code:…` (verificación, la da Brevo) |
   | CNAME | `brevo1._domainkey` | el destino `….dkim.brevo.com` que indique Brevo |
   | CNAME | `brevo2._domainkey` | el destino `….dkim.brevo.com` que indique Brevo |
   | TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:rua@dmarc.brevo.com` |
   | TXT | `@` | `v=spf1 include:spf.brevo.com ~all` |

   niage.eu no tiene hoy ni SPF ni DMARC (solo un TXT de verificación de Canva, que se queda),
   así que se crean nuevos. El SPF no es imprescindible con Brevo (DKIM basta para DMARC), pero
   no estorba porque el dominio no envía correo por otra vía. niage.eu **no tiene MX**: las
   respuestas a encuestas@niage.eu no llegarían a ningún buzón.
3. Remitente en Brevo: `encuestas@niage.eu`, nombre «Encuestas CIS-SFP».
4. Clave SMTP en Brevo (SMTP & API → SMTP keys) y en Supabase, Authentication → Emails → SMTP
   Settings: host `smtp-relay.brevo.com`, puerto `587`, usuario el login SMTP de Brevo,
   contraseña la clave SMTP, remitente `encuestas@niage.eu`, nombre «Encuestas CIS-SFP». La clave
   solo se escribe en el panel de Supabase; nunca en git.
5. Authentication → Rate Limits: subir el límite de correos por hora (por ejemplo, 60) cuando
   el SMTP propio esté activo.

## 5. Carga de los datos reales en la nube (preparada, pendiente de autorización del colegio)

**Qué se sube** (todo sale de `datos_locales/`, que no va a git; la carga va directa a la base
de datos por conexión cifrada, sin pasar por el alojamiento web):

| Paso | Orden | Qué sube |
|---|---|---|
| 1 | `etl/cargar_2526.py --remoto` | 8 cuestionarios, 890 respuestas, unas 132.000 valoraciones, diccionario de 340 preguntas, tramos de tutoría (18) y atribuciones por nombre (388). Sin IP, fechas, identificadores, sexo ni respuestas abiertas; los nombres que escriben los alumnos no se cargan, solo el docente atribuido. |
| 2 | `etl/cargar_asignaciones.py datos_locales/asignacion_2526_desde_alexia.xlsx --remoto` | 799 asignaciones de 97 docentes: nombre, apellidos, correo del colegio, departamento y situación (alta o baja). **Son datos personales del personal docente**: por eso hace falta la autorización. |
| 3 | `etl/cargar_responsables.py --remoto` | 9 cargos de jefe de departamento y 4 del Equipo de Individuación (nombre y correo). |

Requisito: `DATABASE_URL` en el `.env` de Rodrigo con la cadena de conexión del proyecto
(Supabase → Connect → *Session pooler*, IPv4), con su contraseña. Solo en su equipo; nunca en git.

**Cómo se comprueba**

1. `etl/validar_2526.py --remoto`: la misma validación que en local (tabla de control, 494
   preguntas, asignaturas, grupos, etapas y segmentos) contra la nube, dentro de una transacción
   que se deshace. Informe en `datos_locales/informes/validacion_2526_nube.md`, que debe dar el
   mismo resultado que `validacion_2526.md` (hoy: todo en verde, sin diferencias).
2. Recuento de la nube igual al local: `etl/borrar_2526.py --remoto` sin `--confirmar` solo muestra
   el recuento (cuestionarios, respuestas, valoraciones, atribuciones, tramos, grupos, asignaturas,
   departamentos, asignaciones, cargos, personas y preguntas).
3. `npx supabase test db --linked` (los tests usan su propio curso inventado y no dejan nada).
4. Revisión en la web por Rodrigo: Inicio, Alumnos, Familias, Personal e informes, con la franja
   «Resultados en validación».

**Cómo se borraría:** `etl/borrar_2526.py --remoto --confirmar`. Borra en una sola transacción
todo lo del curso 2025/26 (respuestas, catálogo, asignaciones, cargos, atribuciones y las
personas y preguntas que ya no use ningún curso), comprueba que no queda nada y, si quedara algo,
lo deshace todo. No toca usuarios, perfiles ni el registro de actividad. Probado en local
(borrado completo, recarga y validación en verde).

**Franja de validación:** la aplicación y los PDF muestran «Resultados en validación. Pendientes de
revisión final con el Colegio». Se quita poniendo `VITE_AVISO_VALIDACION=no` en las variables de
Clever Cloud y volviendo a desplegar.
