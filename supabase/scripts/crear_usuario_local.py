"""Crea un usuario de prueba en Supabase local, con su perfil. Solo para desarrollo: el alta
real será por invitación (paso 4).

Uso (con Supabase arrancado):
    python3 supabase/scripts/crear_usuario_local.py CORREO CONTRASEÑA ROL [ETAPA] [NOMBRE]

    ROL: direccion o coordinacion (los administradores necesitan doble factor: ver
    probar_mfa_local.py). ETAPA solo para coordinación: infantil, primaria, pai, bachillerato.

Ejemplo:
    python3 supabase/scripts/crear_usuario_local.py direccion@prueba.local Prueba-2026 direccion
"""

import subprocess
import sys

from probar_mfa_local import CONTENEDOR_DB, estado_local, peticion


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__)
        return 1
    correo, clave, rol = sys.argv[1:4]
    etapa = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else None
    nombre = sys.argv[5] if len(sys.argv) > 5 else correo.split("@")[0].replace(".", " ").title()
    if rol not in ("direccion", "coordinacion") or (rol == "coordinacion") != (etapa is not None):
        print("ROL debe ser direccion, o coordinacion con ETAPA.")
        return 1

    env = estado_local()
    estado, usuario = peticion(env["API_URL"], "POST", "/auth/v1/admin/users",
                               {"email": correo, "password": clave, "email_confirm": True},
                               clave=env["SERVICE_ROLE_KEY"])
    if estado != 200:
        print("No se pudo crear el usuario:", usuario.get("msg") or usuario)
        return 1
    etapa_sql = f"'{etapa}'" if etapa else "null"
    nombre_sql = nombre.replace("'", "''")
    subprocess.run(["docker", "exec", CONTENEDOR_DB, "psql", "-U", "postgres", "-qc",
                    f"insert into public.usuario_perfil (id, nombre, rol, etapa) "
                    f"values ('{usuario['id']}', '{nombre_sql}', '{rol}', {etapa_sql})"], check=True)
    print(f"Creado {correo} ({rol}{', ' + etapa if etapa else ''}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
