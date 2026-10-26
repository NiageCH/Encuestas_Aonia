"""Copia completa de la base de la nube y prueba de restauración en una base local aparte.

Uso (desde la raíz del proyecto, con Docker arrancado y DATABASE_URL de la nube en .env):
    .venv/bin/python supabase/scripts/copia_nube.py

1. Copia en datos_locales/copias/nube_<fecha_hora>/ (fuera de git): roles.sql, esquema.sql y datos.sql (formato de
   Supabase para restaurar) y completa.dump (pg_dump 17 de toda la base), con sus huellas SHA-256.
2. Levanta una segunda Supabase local, con otro nombre y los puertos 564xx (no toca la de desarrollo), restaura la
   copia en una sola transacción y la apaga y borra al terminar.
3. Compara la base restaurada con la nube: recuento del curso, validación completa contra los valores de control, y
   usuarios, perfiles, factores de doble factor y registro de actividad. Si algo no coincide, termina con error.

Solo lee de la nube: el recuento usa borrar_2526.py sin --confirmar y la validación deshace lo que hace.
"""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ / "etl"))
from cargar_2526 import url_bd  # noqa: E402

PY = str(RAIZ / ".venv/bin/python")
RESTAURADA = "postgresql://postgres:postgres@127.0.0.1:56422/postgres"
CONTENEDOR = "supabase_db_restauracion-encuestas"
CONTEO_AUTH = ("select 'usuarios ' || (select count(*) from auth.users) || ', perfiles ' || (select count(*) from public.usuario_perfil)"
               " || ', factores ' || (select count(*) from auth.mfa_factors) || ', registro ' || (select count(*) from public.registro_actividad)")


def ejecutar(*args: str, cwd: Path = RAIZ, env: dict | None = None, entrada: str | None = None) -> str:
    r = subprocess.run(list(args), cwd=cwd, env=env, input=entrada, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"Falló: {' '.join(args[:4])}…\n{r.stderr[-1500:]}")
    return r.stdout


def copiar(destino: Path) -> None:
    destino.mkdir(parents=True)
    for nombre, extra in (("roles.sql", ["--role-only"]), ("esquema.sql", []), ("datos.sql", ["--use-copy", "--data-only"])):
        ejecutar("npx", "supabase", "db", "dump", "--linked", "-f", str(destino / nombre), *extra)
    env = dict(os.environ, URL_NUBE=url_bd(True))
    ejecutar("docker", "run", "--rm", "-e", "URL_NUBE", "-v", f"{destino}:/out", "postgres:17", "sh", "-c",
             'timeout 600 pg_dump "$URL_NUBE" --format=custom --no-owner --file=/out/completa.dump', env=env)   # sin colgarse si se corta la conexión
    with open(destino / "SHA256SUMS", "w") as f:
        for p in sorted(destino.iterdir()):
            if p.name != "SHA256SUMS":
                f.write(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n")


def levantar_aparte(trabajo: Path) -> None:
    (trabajo / "supabase").mkdir(parents=True)
    shutil.copytree(RAIZ / "supabase/templates", trabajo / "supabase/templates")
    s = (RAIZ / "supabase/config.toml").read_text()
    s = re.sub(r'^project_id = ".*"', 'project_id = "restauracion-encuestas"', s, count=1, flags=re.M)
    s = re.sub(r"\b554(\d\d)\b", r"564\1", s)
    s = s[:s.index("[remotes.")] if "[remotes." in s else s
    s = re.sub(r"\n\[functions\.[^\]]+\]\nverify_jwt = false\n", "\n", s)
    (trabajo / "supabase/config.toml").write_text(s)
    ejecutar("npx", "--prefix", str(RAIZ), "supabase", "start", "-x",
             "studio,imgproxy,storage-api,edge-runtime,logflare,vector,realtime,mailpit,postgres-meta,supavisor,gotrue,kong,postgrest", cwd=trabajo)


def restaurar(copia: Path) -> None:
    sql = (copia / "roles.sql").read_text() + (copia / "esquema.sql").read_text() + "\nSET session_replication_role = replica;\n" + (copia / "datos.sql").read_text()
    ejecutar("docker", "exec", "-i", CONTENEDOR, "psql", "-U", "supabase_admin", "-d", "postgres", "-X", "-q",
             "--single-transaction", "-v", "ON_ERROR_STOP=1", entrada=sql)


def recuento(env_db: str | None) -> str:
    env = dict(os.environ, **({"DATABASE_URL": env_db} if env_db else {}))
    salida = ejecutar(PY, "etl/borrar_2526.py", *([] if env_db else ["--remoto"]), env=env)
    return "\n".join(salida.splitlines()[1:])


def validacion(env_db: str | None) -> str:
    env = dict(os.environ, **({"DATABASE_URL": env_db} if env_db else {}))
    ejecutar(PY, "etl/validar_2526.py", *([] if env_db else ["--remoto"]), env=env)
    texto = (RAIZ / "datos_locales/informes/validacion_2526.md").read_text()
    return "\n".join(l for l in texto.splitlines() if not l.startswith("Generado"))


def main() -> int:
    import psycopg
    copia = RAIZ / "datos_locales/copias" / f"nube_{datetime.now():%Y-%m-%d_%H%M}"
    trabajo = Path(os.environ.get("TMPDIR", "/tmp")) / "restauracion-encuestas"
    print(f"1. Copia de la nube en {copia.relative_to(RAIZ)}")
    copiar(copia)
    print("   " + ", ".join(f"{p.name} ({p.stat().st_size // 1024} KB)" for p in sorted(copia.iterdir()) if p.name != "SHA256SUMS"))
    print("2. Restauración en una Supabase local aparte (puertos 564xx)")
    shutil.rmtree(trabajo, ignore_errors=True)
    levantar_aparte(trabajo)
    fallos = []
    try:
        restaurar(copia)
        print("3. Comparación con la nube")
        if recuento(RESTAURADA) != recuento(None):
            fallos.append("recuento")
        if validacion(RESTAURADA) != validacion(None):
            fallos.append("validación")
        with psycopg.connect(url_bd(True)) as nube, psycopg.connect(RESTAURADA) as rest:
            a, b = nube.execute(CONTEO_AUTH).fetchone()[0], rest.execute(CONTEO_AUTH).fetchone()[0]
        print(f"   nube:       {a}\n   restaurada: {b}")
        if a != b:
            fallos.append("usuarios y registro")
    finally:
        ejecutar("npx", "--prefix", str(RAIZ), "supabase", "stop", "--no-backup", cwd=trabajo)
        shutil.rmtree(trabajo, ignore_errors=True)
    if fallos:
        print("LA RESTAURACIÓN NO COINCIDE CON LA NUBE: " + ", ".join(fallos) + ". No sigas.")
        return 1
    print("   Recuento, validación, usuarios y registro: idénticos. Copia comprobada.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
