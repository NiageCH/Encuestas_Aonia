"""Prueba en local el doble factor obligatorio del administrador.

Crea un administrador de prueba, entra con contraseña (aal1), comprueba que las RPC lo
rechazan, da de alta un factor TOTP, lo verifica (aal2) y comprueba que ya puede
consultar. Solo para Supabase en local: lee las claves de `npx supabase status`.

Uso (con Supabase arrancado):
    python3 supabase/scripts/probar_mfa_local.py

Borra los datos de prueba con `npm run db:reset`.
"""

import base64
import hashlib
import hmac
import json
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.request

CONTENEDOR_DB = "supabase_db_encuestas-cis-sfp"
CORREO = "admin.prueba@ejemplo.test"
CLAVE = "Prueba-local-2026"
FILTRO = {"curso": "2025/26", "colectivo": "familias"}


def estado_local() -> dict:
    salida = subprocess.run(["npx", "supabase", "status", "-o", "env"],
                            capture_output=True, text=True, check=True).stdout
    valores = dict(linea.split("=", 1) for linea in salida.splitlines() if "=" in linea)
    return {k: v.strip('"') for k, v in valores.items()}


def peticion(base, metodo, ruta, cuerpo=None, token=None, clave=None):
    req = urllib.request.Request(
        base + ruta, method=metodo,
        data=json.dumps(cuerpo).encode() if cuerpo is not None else None,
        headers={"apikey": clave, "Authorization": f"Bearer {token or clave}",
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or "null")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or "null")


def codigo_totp(secreto: str) -> str:
    clave = base64.b32decode(secreto + "=" * (-len(secreto) % 8))
    h = hmac.new(clave, struct.pack(">Q", int(time.time()) // 30), hashlib.sha1).digest()
    o = h[-1] & 15
    return "%06d" % ((struct.unpack(">I", h[o:o + 4])[0] & 0x7FFFFFFF) % 1_000_000)


def aal(token: str) -> str:
    carga = token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(carga + "=" * (-len(carga) % 4)))["aal"]


def sql(sentencia: str) -> None:
    subprocess.run(["docker", "exec", CONTENEDOR_DB, "psql", "-U", "postgres", "-qc", sentencia], check=True)


def mfa_activo() -> bool:
    salida = subprocess.run(["docker", "exec", CONTENEDOR_DB, "psql", "-U", "postgres", "-qAt", "-c",
                             "select permisos.mfa_obligatorio()"], capture_output=True, text=True, check=True).stdout.strip()
    return salida == "t"


def main() -> int:
    if not mfa_activo():
        print("El doble factor está desactivado en esta base de datos local (app.mfa_admin_obligatorio = off).")
        print("Para probarlo, actívalo: docker exec supabase_db_encuestas-cis-sfp psql -U supabase_admin -d postgres "
              "-c \"alter database postgres reset app.mfa_admin_obligatorio\" y reinicia la API.")
        return 0
    env = estado_local()
    base, anon, servicio = env["API_URL"], env["ANON_KEY"], env["SERVICE_ROLE_KEY"]

    estado, usuario = peticion(base, "POST", "/auth/v1/admin/users",
                               {"email": CORREO, "password": CLAVE, "email_confirm": True}, clave=servicio)
    if estado != 200:
        print("No se pudo crear el usuario de prueba (¿ya existe? ejecuta npm run db:reset):", usuario)
        return 1
    sql("insert into public.curso (nombre) values ('2025/26') on conflict do nothing;"
        "insert into public.cuestionario (curso_id, colectivo, codigo, titulo)"
        " select id, 'familias', 'FAM_PRUEBA', 'Prueba' from public.curso where nombre = '2025/26'"
        " on conflict do nothing;"
        f"insert into public.usuario_perfil (id, nombre, rol) values ('{usuario['id']}', 'Admin de prueba', 'administrador');")

    _, sesion = peticion(base, "POST", "/auth/v1/token?grant_type=password",
                         {"email": CORREO, "password": CLAVE}, clave=anon)
    token1 = sesion["access_token"]
    estado, r = peticion(base, "POST", "/rest/v1/rpc/resumen", {"p_filtro": FILTRO}, token1, anon)
    print(f"1. Login con contraseña: {aal(token1)}. RPC: {estado} {r.get('message')}")
    ok = estado == 403

    _, factor = peticion(base, "POST", "/auth/v1/factors", {"factor_type": "totp"}, token1, anon)
    _, reto = peticion(base, "POST", f"/auth/v1/factors/{factor['id']}/challenge", {}, token1, anon)
    _, verif = peticion(base, "POST", f"/auth/v1/factors/{factor['id']}/verify",
                        {"challenge_id": reto["id"], "code": codigo_totp(factor["totp"]["secret"])}, token1, anon)
    token2 = verif["access_token"]
    estado, r = peticion(base, "POST", "/rest/v1/rpc/resumen", {"p_filtro": FILTRO}, token2, anon)
    print(f"2. Tras verificar TOTP: {aal(token2)}. RPC: {estado}")
    ok = ok and estado == 200

    print("Correcto: el administrador necesita aal2." if ok else "FALLO: revisa permisos.exigir().")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
