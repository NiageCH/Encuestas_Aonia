"""Prueba en local el circuito de invitación (§7.5) de principio a fin:
administrador con doble factor -> invitación -> correo en el buzón de pruebas -> perfil y
registro de actividad -> reenvío -> rechazo a quien no es administrador.

Uso (con Supabase arrancado, incluidas las Edge Functions):
    python3 supabase/scripts/probar_invitacion_local.py

Crea de nuevo un administrador de prueba (admin.invita@ejemplo.test) y una persona
invitada con un correo nuevo en cada ejecución (@ejemplo.test). Se borran con npm run db:reset.
"""

import json
import re
import subprocess
import sys
import time
import urllib.request

from probar_mfa_local import CONTENEDOR_DB, aal, codigo_totp, estado_local, peticion

ADMIN, CLAVE = "admin.invita@ejemplo.test", "Prueba-local-2026"
BUZON = "http://127.0.0.1:55424/api/v1"


def sql(sentencia: str) -> str:
    return subprocess.run(["docker", "exec", CONTENEDOR_DB, "psql", "-U", "postgres", "-qAt", "-c", sentencia],
                          capture_output=True, text=True, check=True).stdout.strip()


def funcion(base, anon, token, cuerpo):
    req = urllib.request.Request(f"{base}/functions/v1/admin-usuarios", method="POST", data=json.dumps(cuerpo).encode(),
                                 headers={"apikey": anon, "Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or "{}")


def correos_para(destino: str) -> list:
    with urllib.request.urlopen(f"{BUZON}/search?query=to:{destino}") as r:
        return json.loads(r.read()).get("messages", [])


class SinRedireccion(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def seguir_enlace(destino: str, indice: int = -1) -> dict:
    """Abre el enlace del correo (el más reciente) sin seguir la redirección y devuelve los
    parámetros con los que Supabase vuelve a la aplicación (tras el «#»)."""
    mensajes = sorted(correos_para(destino), key=lambda m: m["Created"])
    with urllib.request.urlopen(f"{BUZON}/message/{mensajes[indice]['ID']}") as r:
        html = json.loads(r.read())["HTML"]
    enlace = re.search(r'href="([^"]+/verify\?[^"]+)"', html).group(1).replace("&amp;", "&")
    abridor = urllib.request.build_opener(SinRedireccion)
    try:
        abridor.open(enlace)
    except urllib.error.HTTPError as e:
        destino_app = e.headers["Location"]
    return {"destino": destino_app.split("#")[0], **dict(x.split("=", 1) for x in destino_app.split("#", 1)[1].split("&"))}


def main() -> int:
    env = estado_local()
    base, anon, servicio = env["API_URL"], env["ANON_KEY"], env["SERVICE_ROLE_KEY"]
    fallos = 0

    def comprobar(ok: bool, texto: str):
        nonlocal fallos
        fallos += not ok
        print(("  ✔ " if ok else "  ✘ ") + texto)

    # Administrador de prueba con TOTP, nuevo en cada ejecución (el secreto del factor no se guarda).
    previo = sql(f"select id from auth.users where email = '{ADMIN}'")
    if previo:
        peticion(base, "DELETE", f"/auth/v1/admin/users/{previo}", None, clave=servicio)
    _, u = peticion(base, "POST", "/auth/v1/admin/users", {"email": ADMIN, "password": CLAVE, "email_confirm": True}, clave=servicio)
    sql(f"insert into public.usuario_perfil (id, nombre, rol) values ('{u['id']}', 'Admin que invita', 'administrador')")
    _, s = peticion(base, "POST", "/auth/v1/token?grant_type=password", {"email": ADMIN, "password": CLAVE}, clave=anon)
    t1 = s["access_token"]
    _, f = peticion(base, "POST", "/auth/v1/factors", {"factor_type": "totp", "friendly_name": f"prueba-{time.time()}"}, t1, anon)
    _, reto = peticion(base, "POST", f"/auth/v1/factors/{f['id']}/challenge", {}, t1, anon)
    _, v = peticion(base, "POST", f"/auth/v1/factors/{f['id']}/verify", {"challenge_id": reto["id"], "code": codigo_totp(f["totp"]["secret"])}, t1, anon)
    t2 = v["access_token"]
    print(f"Administrador: {aal(t2)}")

    estado, r = funcion(base, anon, t1, {"accion": "invitar", "nombre": "X", "correo": "x@ejemplo.test", "rol": "direccion"})
    comprobar(estado == 403, f"sin doble factor (aal1), la función rechaza la invitación ({estado})")

    correo = f"invitada.{int(time.time())}@ejemplo.test"
    estado, r = funcion(base, anon, t2, {"accion": "invitar", "nombre": "Persona Invitada", "correo": correo, "rol": "coordinacion", "etapa": "pai"})
    comprobar(estado == 200, f"invitación enviada ({estado} {r.get('error', '')})")
    nuevo = r.get("id")
    time.sleep(1.5)
    mensajes = correos_para(correo)
    comprobar(len(mensajes) == 1 and "Acceso a las encuestas" in mensajes[0]["Subject"], f"el correo de invitación llega al buzón de pruebas ({len(mensajes)})")
    comprobar(sql(f"select rol || '/' || etapa from public.usuario_perfil where id = '{nuevo}'") == "coordinacion/pai", "perfil creado con rol y etapa")
    comprobar(sql(f"select count(*) from public.registro_actividad where accion = 'invitacion' and detalle ->> 'usuario' = '{nuevo}'") == "1",
              "la invitación queda en el registro de actividad")

    estado, r = funcion(base, anon, t2, {"accion": "invitar", "nombre": "Repetida", "correo": correo, "rol": "direccion"})
    comprobar(estado == 409, f"un correo ya invitado no se duplica ({estado} {r.get('error', '')})")

    estado, r = funcion(base, anon, t2, {"accion": "reenviar", "id": nuevo})
    comprobar(estado == 200, f"reenvío de la invitación ({estado} {r.get('error', '')})")
    time.sleep(1.5)
    comprobar(len(correos_para(correo)) == 2, "llega un segundo correo")
    comprobar(sql(f"select count(*) from public.registro_actividad where accion = 'reenvio_invitacion' and detalle ->> 'usuario' = '{nuevo}'") == "1",
              "el reenvío queda en el registro de actividad")

    # Aceptar la invitación: el enlace vuelve a la aplicación con type=invite y una sesión,
    # con la que se crea la contraseña (lo que hace la pantalla «Crea tu contraseña»).
    vuelta = seguir_enlace(correo)
    comprobar(vuelta.get("type") == "invite" and vuelta["destino"].startswith("http://127.0.0.1:5173"),
              f"el enlace de invitación vuelve a la aplicación con type=invite ({vuelta.get('type')}, {vuelta['destino']})")
    estado, _ = peticion(base, "PUT", "/auth/v1/user", {"password": "Invitada-2026"}, vuelta["access_token"], anon)
    comprobar(estado == 200, "la persona invitada crea su contraseña")
    estado, s3 = peticion(base, "POST", "/auth/v1/token?grant_type=password", {"email": correo, "password": "Invitada-2026"}, clave=anon)
    comprobar(estado == 200, "y entra con ella")
    time.sleep(1)
    comprobar(sql(f"select ultimo_acceso is not null from public.usuario_perfil where id = '{nuevo}'") == "t",
              "el último acceso queda registrado al entrar")
    estado, r = funcion(base, anon, t2, {"accion": "reenviar", "id": nuevo})
    comprobar(estado == 409, f"no se reenvía la invitación a quien ya ha entrado ({estado})")

    # Recuperar la contraseña: type=recovery
    peticion(base, "POST", "/auth/v1/recover", {"email": correo}, clave=anon)
    time.sleep(1.5)
    vuelta = seguir_enlace(correo)
    comprobar(vuelta.get("type") == "recovery", f"el enlace de recuperación vuelve con type=recovery ({vuelta.get('type')})")
    estado, _ = peticion(base, "PUT", "/auth/v1/user", {"password": "Cambiada-2026"}, vuelta["access_token"], anon)
    estado2, _ = peticion(base, "POST", "/auth/v1/token?grant_type=password", {"email": correo, "password": "Cambiada-2026"}, clave=anon)
    comprobar(estado == 200 and estado2 == 200, "la contraseña nueva sirve para entrar")

    _, sd = peticion(base, "POST", "/auth/v1/token?grant_type=password", {"email": "rodrigo@prueba.local", "password": "Sfpaula-59d6ac"}, clave=anon)
    if "access_token" in sd:
        estado, r = funcion(base, anon, sd["access_token"], {"accion": "invitar", "nombre": "X", "correo": "y@ejemplo.test", "rol": "direccion"})
        comprobar(estado == 403, f"dirección (no administrador) no puede invitar ({estado})")

    print("Correcto." if not fallos else f"{fallos} comprobación(es) fallida(s).")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
