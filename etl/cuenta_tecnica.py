"""Cuenta técnica de verificación: el usuario de Dirección temporal con el que validar_2526.py y
verificar_informes_2526.py piden los resultados a la plataforma.

La cuenta solo existe dentro de transacciones que se deshacen: se crea, se usa y desaparece en la misma transacción,
sin confirmarse nunca. Por eso ninguna otra sesión la ve (tampoco el servicio de acceso), no tiene contraseña ni
puede iniciar sesión, y si el script falla, se interrumpe o se corta la conexión, la base de datos deshace la
transacción y no queda nada.

Para que el registro de actividad lo explique (el Colegio no debe ver un alta de Dirección sin explicación), cada uso
deja dos entradas confirmadas, en una transacción aparte: «alta temporal» al empezar y «baja» al terminar, con el
resultado. Acción `verificacion_tecnica`, a nombre de «Cuenta técnica de verificación (Niage)».
"""
from __future__ import annotations

import atexit
import json
import signal
import sys
import uuid
from datetime import datetime, timezone

import psycopg

NOMBRE = "Cuenta técnica de verificación (Niage)"
CORREO = "verificacion@local"


class Uso:
    """Un uso de la cuenta técnica: `empezar()` deja el alta temporal en el registro y `terminar()` la baja, también si
    el script sale por un error, por Ctrl+C o por SIGTERM. (Si se mata el proceso con SIGKILL no se puede escribir
    la baja, pero la cuenta tampoco queda: nunca se confirma.)"""

    def __init__(self, url: str, script: str, base: str):
        self.url = url
        self.script = script
        self.base = base
        self.id = str(uuid.uuid4())
        self.resultado = "interrumpida"
        self.cifras: int | None = None
        self._terminado = False

    def _registrar(self, fase: str, extra: dict) -> None:
        detalle = {"fase": fase, "script": self.script, "base": self.base, "uso": self.id, "cuenta": CORREO, **extra}
        for intento in range(3):
            try:
                with psycopg.connect(self.url, autocommit=True) as conn:
                    conn.execute("insert into public.registro_actividad (usuario_id, accion, detalle, usuario_nombre) "
                                 "values (null, 'verificacion_tecnica', %s, %s)", (json.dumps(detalle), NOMBRE))
                return
            except psycopg.OperationalError:
                if intento == 2:
                    print(f"No se ha podido anotar la {fase} de la cuenta técnica en el registro.", file=sys.stderr)

    def empezar(self) -> "Uso":
        self._registrar("alta", {"inicio": datetime.now(timezone.utc).isoformat()})
        atexit.register(self.terminar)
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
        return self

    def terminar(self) -> None:
        if self._terminado:
            return
        self._terminado = True
        extra = {"fin": datetime.now(timezone.utc).isoformat(), "resultado": self.resultado}
        if self.cifras is not None:
            extra["cifras"] = self.cifras
        self._registrar("baja", extra)

    def __enter__(self) -> "Uso":
        return self.empezar()

    def __exit__(self, *_exc) -> None:
        self.terminar()
