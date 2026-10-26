#!/usr/bin/env bash
# Deja Supabase local listo para probar con los datos reales de 2025/26 (que están en datos_locales/, fuera de git):
# recrea la base de datos con las migraciones, carga encuestas, asignación docente y responsables, crea los
# usuarios de prueba y desactiva en local el doble factor de administradores (solo desarrollo).
#
# Uso, desde la raíz del proyecto y con Docker arrancado:
#     bash supabase/scripts/preparar_local.sh
#
# Las contraseñas de los usuarios de prueba se generan la primera vez y se guardan en
# datos_locales/usuarios_locales.txt (fuera de git). Las siguientes veces se reutilizan.
set -euo pipefail
cd "$(dirname "$0")/../.."

LOCAL=postgresql://postgres:postgres@127.0.0.1:55422/postgres
USUARIOS=datos_locales/usuarios_locales.txt
CONTENEDOR=supabase_db_encuestas-cis-sfp

npx supabase status >/dev/null 2>&1 || npx supabase start
npx supabase db reset

echo "== Carga de 2025/26 (local)"
DATABASE_URL=$LOCAL .venv/bin/python etl/cargar_2526.py | tail -2
DATABASE_URL=$LOCAL .venv/bin/python etl/cargar_asignaciones.py datos_locales/asignacion_2526_desde_alexia.xlsx | tail -1
DATABASE_URL=$LOCAL .venv/bin/python etl/cargar_responsables.py
DATABASE_URL=$LOCAL .venv/bin/python etl/validar_2526.py >/dev/null && echo "Validación de 2025/26: sin diferencias"

echo "== Usuarios de prueba"
if [ ! -f "$USUARIOS" ]; then
  clave() { python3 -c "import secrets,string; a=string.ascii_letters+string.digits; print('L'+''.join(secrets.choice(a) for _ in range(11))+'7')"; }
  {
    echo "# Usuarios de prueba de Supabase LOCAL (no sirven en la nube). Fuera de git."
    echo "admin@prueba.local $(clave) administrador"
    echo "direccion@prueba.local $(clave) direccion"
    echo "coord.bachillerato@prueba.local $(clave) coordinacion bachillerato"
    echo "coord.pai@prueba.local $(clave) coordinacion pai"
  } > "$USUARIOS"
fi
grep -v '^#' "$USUARIOS" | while read -r correo clave rol etapa; do
  rol_alta=$rol; [ "$rol" = "administrador" ] && rol_alta=direccion
  python3 supabase/scripts/crear_usuario_local.py "$correo" "$clave" "$rol_alta" "${etapa:-}" >/dev/null
  if [ "$rol" = "administrador" ]; then
    docker exec "$CONTENEDOR" psql -U postgres -qAt -c \
      "update public.usuario_perfil set rol = 'administrador' where id = (select id from auth.users where email = '$correo')" >/dev/null
  fi
  echo "  $correo ($rol${etapa:+, $etapa})"
done

echo "== Doble factor de administradores desactivado en local (en la nube sigue siendo obligatorio)"
docker exec "$CONTENEDOR" psql -U supabase_admin -d postgres -qc "alter database postgres set app.mfa_admin_obligatorio = 'off'"
docker restart supabase_rest_encuestas-cis-sfp supabase_edge_runtime_encuestas-cis-sfp >/dev/null
echo "Listo. Contraseñas en $USUARIOS"
