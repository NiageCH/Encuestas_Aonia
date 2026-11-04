# Acceso con Microsoft: lo que configura sistemas del Colegio

Guía para Manuel (sistemas del Colegio). Explica qué hay que configurar en Entra ID para que el profesorado y el equipo directivo entren en la plataforma de encuestas con su cuenta de Microsoft del Colegio. Funcionamiento completo en la especificación, §7.11.

Hay que hacerlo **dos veces**, una por entorno:
1. el **entorno de pruebas**, antes;
2. el de **producción**, en el paso a producción en las cuentas del Colegio.

Niage le pasará la dirección de vuelta de cada uno.

## 1. Registrar la aplicación

En el centro de administración de Microsoft Entra: **Aplicaciones › Registros de aplicaciones › Nuevo registro**.

- **Nombre:** «Encuestas CIS-SFP» (para el entorno de pruebas, «Encuestas CIS-SFP (pruebas)»).
- **Tipos de cuenta admitidos:** «Solo las cuentas de este directorio organizativo» (una sola organización).
- **URI de redirección**, tipo **Web**: `https://<proyecto>.supabase.co/auth/v1/callback`. Niage le da la dirección exacta de cada entorno.

## 2. Datos que nos tiene que pasar

- **Id. de aplicación (cliente)** e **Id. de directorio (inquilino)**, en la página «Información general». Pueden ir por correo.
- **Secreto de cliente.** Se crea en «Certificados y secretos › Nuevo secreto de cliente», con caducidad de **12 meses**. Envíe el **valor** (no el identificador del secreto) por un canal aparte, nunca en el mismo correo que los identificadores. Por ejemplo, un enlace de un solo uso, o dictado por teléfono. Niage lo pone directamente en Supabase y no lo guarda en ningún otro sitio.

## 3. Permisos

**Permisos de API › Microsoft Graph › Permisos delegados:** `openid`, `email`, `profile` y `User.Read`.

Después, pulse **«Conceder consentimiento de administrador»**, para que a nadie le salga la pantalla de permisos al entrar.

## 4. Datos opcionales del token

**Configuración de tokens › Agregar notificación opcional › Id:** `email` y `xms_edov`.

`xms_edov` dice a la plataforma que el correo es del dominio verificado del Colegio. Sin él, una cuenta que ya existe en la plataforma no se une a la de Microsoft y la persona no podría entrar.

## 5. Quién puede entrar: asignación obligatoria

**Aplicaciones empresariales › Encuestas CIS-SFP › Propiedades:** «¿Se requiere asignación?» = **Sí**.

En **Usuarios y grupos**, añada:
- el equipo directivo, la coordinación y administración;
- **todo el profesorado y las jefaturas que reciben su informe**: el enlace de cada informe se abre con Microsoft.

Lo más cómodo es un grupo, por ejemplo «Encuestas CIS-SFP».

La plataforma tiene su propio cerrojo: aunque alguien esté asignado, solo entra si Dirección le ha dado acceso en la plataforma o tiene un informe enviado.

## 6. Doble factor: elija una variante

La plataforma no puede comprobar desde fuera si Microsoft ha pedido el doble factor. Lo garantiza el Colegio con una de estas dos variantes. Administración tiene además el doble factor propio de la plataforma.

### Variante A: acceso condicional (necesita Entra ID P1)

Incluido, por ejemplo, en Microsoft 365 A3 o A5.

**Protección › Acceso condicional › Nueva directiva:**
- **Usuarios:** el grupo de la aplicación (o todos).
- **Recursos de destino:** la aplicación «Encuestas CIS-SFP».
- **Conceder:** «Requerir autenticación multifactor» (o una «Seguridad de autenticación» resistente a la suplantación, si ya la usan).
- **Sesión:** no hace falta tocarla.
- **Estado:** primero en «Solo informe» unos días, para ver a quién afectaría. Después, «Activado».

### Variante B: valores predeterminados de seguridad (sin licencia P1)

**Identidad › Información general › Propiedades › Administrar valores predeterminados de seguridad** = **Habilitado**.

- Obliga a todas las cuentas del Colegio a registrar un segundo factor (Microsoft Authenticator) y lo pide cuando Microsoft ve riesgo, siempre a los administradores.
- Es para todo el Colegio, no solo para esta aplicación, y no se puede usar a la vez que el acceso condicional.
- Si ya está habilitado, no hay que hacer nada.

Díganos qué variante aplican. Queda anotada en la documentación técnica.

## 7. Cuentas de prueba (solo para el entorno de pruebas)

Necesitamos que cree estas cuentas, o que use cuentas reales que se presten a la prueba:

| Cuenta | Asignada a la aplicación | En la plataforma | Resultado esperado |
|---|---|---|---|
| Prueba 1 | Sí | Con acceso de Dirección | Entra |
| Prueba 2 | Sí | Sin acceso | Rechazada: «No tiene acceso a la plataforma» |
| Prueba 3 | No | Con acceso | Rechazada por Microsoft (no asignada) |
| Prueba 4 | Sí | Ya tiene cuenta con contraseña y el mismo correo | Entra con Microsoft y conserva su rol; ya no puede entrar con contraseña |
| Prueba 5 (docente) | Sí | Sin acceso; recibe un informe de prueba | Abre su informe con Microsoft; con la cuenta de Prueba 1, no |

Al terminar las pruebas, se borran o se desasignan.

## 8. Renovación del secreto (cada 12 meses)

1. Un mes antes de que caduque, Niage se lo recuerda: la fecha está en la lista de claves, y el aviso a administración está previsto en la Fase 2.
2. Manuel crea un **secreto nuevo sin borrar el viejo** y nos pasa el valor como en el punto 2.
3. Niage lo cambia en Supabase (Autenticación › Proveedores › Azure) y prueba a entrar.
4. Manuel borra el secreto viejo.
5. Queda anotado, con la fecha nueva de caducidad.

Si el secreto llegara a caducar, nadie del Colegio podría entrar con Microsoft hasta cambiarlo. La cuenta de emergencia, con contraseña y doble factor, sigue entrando.

## 9. Qué datos recibe la plataforma de Microsoft

El nombre, el correo y el identificador de la cuenta en Microsoft. La plataforma usa el correo para saber quién es. No lee el buzón, ni el calendario, ni ningún otro dato.
