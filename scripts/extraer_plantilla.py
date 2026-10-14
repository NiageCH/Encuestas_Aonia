"""Copia de la plantilla de la intranet lo que la aplicación usa tal cual (§8):
  * bloques A (fuente Raleway embebida) y B (estilos de la intranet) -> src/estilos/intranet.css
  * logo del colegio (cabecera), logo blanco (pie) y favicono -> src/recursos/

Uso: python3 scripts/extraer_plantilla.py
No se toca nada a mano en los ficheros generados: si cambia la plantilla, se vuelve a ejecutar.
"""

import base64
import re
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
html = (RAIZ / "referencia" / "plantilla-intranet-cis-sfp.html").read_text(encoding="utf-8")

estilo = re.search(r"<style>\n(.*?)</style>", html, re.S).group(1)
inicio = estilo.index("/* ===")                       # comienzo del bloque A
fin = estilo.index("   C · ")                          # comienzo del bloque C
fin = estilo.rindex("/* ===", 0, fin)
ab = estilo[inicio:fin].rstrip() + "\n"
assert "A · FONT" in ab and "B · INTRANET CIS-SFP STYLES" in ab and "C · " not in ab
cabecera = ("/* Generado por scripts/extraer_plantilla.py a partir de referencia/plantilla-intranet-cis-sfp.html.\n"
            "   Bloques A y B copiados tal cual. No editar: los estilos propios van en encuestas.css (bloque C). */\n\n")
(RAIZ / "src" / "estilos").mkdir(parents=True, exist_ok=True)
(RAIZ / "src" / "estilos" / "intranet.css").write_text(cabecera + ab, encoding="utf-8")


def guardar(patron: str, nombre: str) -> None:
    m = re.search(patron, html, re.S)
    tipo, datos = m.group(1), m.group(2)
    destino = RAIZ / "src" / "recursos" / f"{nombre}.{tipo}"
    destino.parent.mkdir(parents=True, exist_ok=True)
    destino.write_bytes(base64.b64decode(datos))
    print(f"{destino.relative_to(RAIZ)}: {destino.stat().st_size} bytes")


guardar(r'<link rel="icon" type="image/(png)" href="data:image/png;base64,([^"]+)"', "favicon")
guardar(r'<img class="brand-logo" src="data:image/(webp);base64,([^"]+)"', "logo")
guardar(r'<a class="f-logo"[^>]*><img src="data:image/(webp);base64,([^"]+)"', "logo-blanco")
print(f"src/estilos/intranet.css: {len(ab)} caracteres (bloques A y B)")
