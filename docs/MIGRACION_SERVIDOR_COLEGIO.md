# Migración al servidor del colegio

Plan para pasar la plataforma de Supabase en la nube y Clever Cloud a un servidor Linux del colegio, en su proveedor (Convive o Cedemon), con el software de Supabase de código abierto instalado con Docker. Estado: **borrador para Rodrigo** (26/10/2026).

Lo que no cambia: el código de la aplicación, las migraciones, las reglas de anonimato (mínimo de 5, supresión complementaria, sin datos identificativos), el doble factor de los administradores y la forma de trabajar (todo probado en local antes de tocar el servidor).

---

## 1. Respuestas previas

### 1.1 Web y API con un único nombre: sí
La API de Supabase autoalojado entra por una pasarela en el puerto 8000 con rutas fijas (`/rest/v1/`, `/auth/v1/`, `/functions/v1/`, `/storage/v1/`, `/realtime/v1/`). Delante se pone un proxy con HTTPS (Caddy, como hoy en Clever Cloud) que en `https://encuestas.sfpaula.com`:
- envía `/rest/v1/*`, `/auth/v1/*` y `/functions/v1/*` a la pasarela de Supabase;
- sirve la web (los ficheros de `dist/`) en todo lo demás.

La aplicación usa como dirección de Supabase la misma `https://encuestas.sfpaula.com`; la política de seguridad de contenidos se queda en `connect-src 'self'`. El panel de administración de Supabase (Studio) **no se publica**: solo se abre desde el equipo de Niage por un túnel SSH.

### 1.2 Correo por el relay de Microsoft 365 autenticado por IP: sí, con una condición de red
El módulo de acceso (GoTrue) solo exige servidor, puerto y remitente; el usuario y la contraseña son opcionales («si el servidor de correo requiere autenticación»). Se configura así:
- `SMTP_HOST`: el extremo del conector de Microsoft 365 del colegio (del tipo `sfpaula-com.mail.protection.outlook.com`);
- `SMTP_PORT=25`;
- `SMTP_ADMIN_EMAIL=encuestas@sfpaula.com` y `SMTP_SENDER_NAME="Encuestas CIS-SFP"`;
- `SMTP_USER` y `SMTP_PASS` **sin definir** (quitadas también del `docker-compose.yml`, no como texto vacío).

Condiciones:
1. **El proveedor debe permitir la salida por el puerto 25.** Muchos proveedores la bloquean por defecto en sus servidores; hay que pedir que la abran hacia Microsoft 365.
2. El servidor necesita una **IP pública fija**, que sistemas del colegio añade al conector de entrada de Microsoft 365 («desde el servidor de correo de tu organización», identificado por IP).
3. `encuestas@sfpaula.com` debe ser un dominio aceptado en su Microsoft 365 (lo es, al ser `sfpaula.com`).

**Alternativa recomendada si el puerto 25 no se puede abrir o para ganar robustez: relay local.** Un contenedor de Postfix en el mismo servidor, solo accesible desde la red interna de Docker:
- GoTrue envía a `relay:25` sin autenticación (dentro del servidor no sale nada);
- Postfix reenvía a Microsoft 365 con TLS obligatorio (`smtp_tls_security_level = encrypt`) por el conector de IP, y guarda en cola y reintenta si Microsoft no responde;
- deja un registro propio de envíos para diagnosticar invitaciones que no llegan.

Si el proveedor no abre el puerto 25 de ninguna manera, la salida tendría que ir por otro canal (un servicio de envío como Brevo por el 587, que ya conocemos), y eso lo decide el colegio.

### 1.3 Requisitos: suficientes
| | Pedido | Supabase recomienda | Uso previsto |
|---|---|---|---|
| CPU | 4 vCPU | mínimo 2, recomendado 4 o más | Muy bajo: decenas de usuarios internos y, en campaña, cientos de envíos al día |
| RAM | 8 GB | mínimo 4 GB, recomendado 8 GB o más | Los servicios que usamos caben holgados; quitamos los que no usamos |
| Disco | 100 GB SSD | mínimo 40 GB, recomendado 80 GB o más | La base de datos ocupa hoy 38 MB; el resto, imágenes de Docker, registros y copias locales |
| Sistema | Ubuntu 24.04 o Debian 12 | Debian y Ubuntu, con Docker | Cualquiera de los dos |

Añadiría a la petición:
- **IP pública fija** y salida por el puerto 25 hacia Microsoft 365 (o la alternativa del §1.2).
- **Entrada solo por 80 y 443** (el 80, para el certificado y la redirección a HTTPS). Ningún otro puerto abierto al exterior salvo SSH, limitado a las IP de Niage.
- **Acceso SSH con clave** para Niage, con permisos para usar Docker.
- **Copias de la máquina** por parte del proveedor (instantáneas diarias) y un espacio externo para las copias de la base de datos (§5).

Servicios de Supabase que **no usamos** y se quitan para ahorrar recursos y superficie: Realtime, Storage e imgproxy. Se mantienen: Postgres, Auth (GoTrue), PostgREST, la pasarela, Edge Runtime (las dos funciones: invitaciones y envío del formulario), postgres-meta y Studio (solo por túnel).

---

## 2. Arquitectura en el servidor

```
Internet ──443──▶ Caddy (HTTPS, certificado automático)
                   ├─ /rest/v1/*, /auth/v1/*, /functions/v1/* ──▶ pasarela de Supabase :8000 (solo red interna)
                   │      ├─ PostgREST ──▶ Postgres
                   │      ├─ Auth (GoTrue) ──▶ relay de correo (opcional) ──25──▶ Microsoft 365
                   │      └─ Edge Runtime (admin-usuarios, enviar-respuesta)
                   └─ resto ──▶ web (dist/)
Studio y Postgres: solo en localhost; Niage entra por túnel SSH.
```

Todo con versiones fijas de las imágenes de Docker, anotadas en el repositorio (`despliegue/servidor/`), para que una actualización sea siempre deliberada.

## 3. Configuración que pasa del panel de Supabase a ficheros

En la nube, parte de la configuración vive en el panel. En el servidor, todo va en el `.env` y el `docker-compose.yml` del servidor (los secretos, solo en el servidor y en el gestor de contraseñas de Niage, nunca en git):

| Hoy | En el servidor |
|---|---|
| `supabase/config.toml` sección `[remotes.pruebas]` | Variables de GoTrue: alta libre desactivada, enlaces de 24 horas, contraseñas de 10 con letras y números, doble factor TOTP, `SITE_URL` y lista de direcciones permitidas con `https://encuestas.sfpaula.com` |
| SMTP de Brevo en el panel | SMTP del §1.2 |
| Plantillas de correo en el panel | `MAILER_TEMPLATES_*` apuntando a las plantillas de `supabase/templates/`, servidas por Caddy en una ruta interna |
| Secreto `SITIO_URL` de la función | Variable de Edge Runtime |
| Claves `anon` y `service_role` de la nube | **Claves nuevas**, generadas con un secreto JWT nuevo |
| Copias diarias del plan Pro | Copias propias (§5) |

## 4. Anonimato: registros de acceso

En el servidor somos responsables de los registros. Para cumplir la regla de no guardar IP de quien responde:
- Caddy registra las peticiones **sin la IP** (filtro que la enmascara) y con retención corta (14 días).
- La pasarela de Supabase y Edge Runtime, con el nivel de registro mínimo y la misma retención.
- Se revisa antes de abrir la primera encuesta que ningún registro guarda la IP ni el contenido del envío.

## 5. Copias de seguridad

- **Diaria:** volcado completo de la base (`pg_dump`, el mismo procedimiento que la copia del 26/10), cifrado y enviado fuera del servidor (espacio que indique el proveedor o el colegio). Retención: 30 diarias y 12 mensuales.
- **Instantánea de la máquina** por el proveedor.
- **Prueba de restauración mensual** en una base aparte, comparando recuento y validación, como se hizo el 26/10/2026 con la copia de la nube.

## 6. Plan de migración

| Paso | Qué | Quién | Comprobación |
|---|---|---|---|
| 0 | Elegir proveedor (Convive o Cedemon) y contratar el servidor con los requisitos del §1.3 | Colegio | Acceso SSH de Niage |
| 1 | Pedir al proveedor la salida por el puerto 25 y confirmar la IP fija | Colegio con el proveedor | Prueba de conexión al 25 de Microsoft 365 desde el servidor |
| 2 | Conector de Microsoft 365 para la IP del servidor | Sistemas del colegio | Correo de prueba desde el servidor |
| 3 | Preparar en local el despliegue (`despliegue/servidor/`: compose, Caddy, relay, copias) y probarlo en una máquina virtual igual | Niage | Pila completa en local con los datos restaurados de la copia |
| 4 | Instalar en el servidor: Docker, cortafuegos, actualizaciones automáticas de seguridad, la pila del paso 3 | Niage | Servicios en marcha; Studio y Postgres no accesibles desde fuera |
| 5 | DNS `encuestas.sfpaula.com` hacia la IP del servidor | Sistemas del colegio | Certificado HTTPS emitido |
| 6 | Base de datos: migraciones 1 a la última aprobada y datos de 2025/26 restaurados desde la copia de la nube (procedimiento ya probado) | Niage | Recuento y validación idénticos a la nube; 300 y pico tests pgTAP en verde contra el servidor |
| 7 | Funciones, plantillas y web | Niage | Invitación y recuperación de contraseña reales; doble factor; formulario de prueba de punta a punta |
| 8 | Usuarios: los administradores vuelven a configurar el doble factor (las claves nuevas invalidan las sesiones) | Niage y administradores | Entrada con código |
| 9 | Revisión interna en el servidor (lista de `datos_locales/Revision_interna_2526.xlsx`) | Niage | Lista completa |
| 10 | Corte: se avisa a los usuarios, se deja de usar la nube, se invita al colegio | Rodrigo | Primeros accesos del colegio |
| 11 | Retirada de Supabase en la nube y Clever Cloud tras un periodo de seguridad (30 días), con copia final guardada | Niage | Proyecto y aplicación eliminados; copia final verificada |

Mientras no se haga el corte, la nube actual sigue siendo el entorno de revisión y la vuelta atrás.

## 7. Qué cambia en el repositorio

- Carpeta `despliegue/servidor/` con el `docker-compose.yml` reducido, el `Caddyfile` del servidor, el relay de correo, el script de copias y una guía de operación (sin secretos; un `.env.example` con los nombres).
- `docs/DESPLIEGUE.md`: el servidor como destino; el orden de cada subida pasa a ser GitHub, migraciones contra el servidor (por túnel SSH), tests contra el servidor, web.
- La ETL y la validación siguen igual, apuntando a la base del servidor por el túnel (`DATABASE_URL` local del túnel y `--remoto`).
- `CLAUDE.md` y `README`: arquitectura nueva.

## 8. Decisiones para Rodrigo

1. **Proveedor:** Convive o Cedemon, según quién garantice IP fija, salida por el 25, instantáneas y soporte.
2. **Correo:** directo a Microsoft 365 por el 25 o con relay local (recomendado: relay local, por la cola, los reintentos y el registro de envíos).
3. **Quién administra el sistema operativo:** el proveedor (actualizaciones, parches) o Niage. Recomendado: el proveedor el sistema, Niage la aplicación.
4. **Destino de las copias externas.**
5. **Qué hacemos con la nube actual hasta el corte:** subir allí los cambios pendientes de `fase1-coordinacion` para la revisión interna, o congelarla y revisar directamente en el servidor.
6. **Fase 2 en el servidor:** el formulario público también saldrá por `encuestas.sfpaula.com`; confirmar que el colegio acepta que el servidor reciba las respuestas de familias desde fuera (es una web pública con protección contra envíos automáticos).

## Fuentes
- Supabase, autoalojamiento con Docker: requisitos, servicios, pasarela, HTTPS con proxy y SMTP (https://supabase.com/docs/guides/self-hosting/docker).
- Supabase Auth (GoTrue), configuración: `SMTP_USER` y `SMTP_PASS` opcionales si el servidor de correo no requiere autenticación; plantillas por URL (https://github.com/supabase/auth/blob/master/README.md).
