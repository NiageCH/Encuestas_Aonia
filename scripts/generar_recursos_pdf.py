"""Recursos para los PDF a partir de la plantilla de la intranet (§8: mismo logo y tipografía).

react-pdf no lee WebP ni fuentes variables, así que se derivan de los recursos de la web:
  * src/recursos/pdf/logo.png y logo-blanco.png  <- logos WebP de la plantilla
  * src/recursos/pdf/Raleway-{400,600,700,800}.ttf <- Raleway variable (bloque A), instancias
    estáticas por peso, con los alfabetos latino y latino extendido y las cifras de caja alta y
    ancho fijo por defecto (como lining-nums en la web)

Raleway se distribuye con la licencia SIL Open Font License 1.1, que permite este uso.

Uso: .venv/bin/python scripts/generar_recursos_pdf.py   (tras scripts/extraer_plantilla.py)
"""

import base64
import io
import re
from pathlib import Path

from fontTools.merge import Merger
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from PIL import Image

RAIZ = Path(__file__).resolve().parent.parent
DESTINO = RAIZ / "src" / "recursos" / "pdf"
DESTINO.mkdir(parents=True, exist_ok=True)

for nombre in ("logo", "logo-blanco"):
    img = Image.open(RAIZ / "src" / "recursos" / f"{nombre}.webp")
    img.save(DESTINO / f"{nombre}.png", optimize=True)
    print(f"src/recursos/pdf/{nombre}.png {img.size}")

css = (RAIZ / "src" / "estilos" / "intranet.css").read_text(encoding="utf-8")
subconjuntos = [base64.b64decode(m) for m in re.findall(r"url\(data:font/woff2;base64,([A-Za-z0-9+/=]+)\)", css)]
assert len(subconjuntos) == 2, "se esperaban los subconjuntos latino y latino extendido"

def congelar(fuente: TTFont, rasgos=("lnum", "tnum")) -> None:
    """Hace por defecto las cifras de caja alta y de ancho fijo, como la intranet
    (font-variant-numeric: lining-nums): aplica las sustituciones de esos rasgos a la cmap."""
    if "GSUB" not in fuente:
        return
    gsub = fuente["GSUB"].table
    for rasgo in rasgos:
        mapa = {}
        for fr in gsub.FeatureList.FeatureRecord:
            if fr.FeatureTag != rasgo:
                continue
            for i in fr.Feature.LookupListIndex:
                for st in gsub.LookupList.Lookup[i].SubTable:
                    st = getattr(st, "ExtSubTable", st)
                    if hasattr(st, "mapping"):
                        mapa.update(st.mapping)
        for tabla in fuente["cmap"].tables:
            for cp, glifo in list(tabla.cmap.items()):
                if glifo in mapa:
                    tabla.cmap[cp] = mapa[glifo]


for peso in (400, 600, 700, 800):
    partes = []
    for i, datos in enumerate(subconjuntos):
        f = TTFont(io.BytesIO(datos))
        f = instancer.instantiateVariableFont(f, {"wght": peso})
        congelar(f)
        f.flavor = None
        tmp = DESTINO / f".tmp-{peso}-{i}.ttf"
        f.save(tmp)
        partes.append(tmp)
    unida = Merger().merge([str(p) for p in partes])
    unida.save(DESTINO / f"Raleway-{peso}.ttf")
    for p in partes:
        p.unlink()
    print(f"src/recursos/pdf/Raleway-{peso}.ttf {(DESTINO / f'Raleway-{peso}.ttf').stat().st_size} bytes")
