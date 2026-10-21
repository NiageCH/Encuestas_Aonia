"""Departamentos oficiales del colegio (21/10/2026) y su equivalencia con los nombres que usan
la encuesta de personal 2025/26 y la primera propuesta de asignación."""

from __future__ import annotations

OFICIALES = [
    "Lengua y Literatura Españolas",
    "Lengua y Literatura Inglesas",
    "Adquisición de Lenguas",
    "Matemáticas",
    "Ciencias",
    "Individuos y Sociedades",
    "Artes Escénicas",
    "Artes Visuales y Tecnología",
    "Educación Física",
]

# Sin departamento: no es oficial ni tiene jefe.
OTROS = "Otros"

# Departamento de la matriz de reuniones de la encuesta → departamentos oficiales que cubre.
# Los que no aparecen se llaman igual que el oficial.
EQUIVALENCIAS_ENCUESTA = {
    "Lengua Española y Literatura": ["Lengua y Literatura Españolas"],
    "Artes Visuales y Diseño": ["Artes Visuales y Tecnología"],
    "Inglés y Adquisición de Lenguas": ["Lengua y Literatura Inglesas", "Adquisición de Lenguas"],
}

# Nombre de la primera propuesta (y de la revisión del colegio) → oficial. «Inglés y
# Adquisición de Lenguas» no está: se reparte según lo que imparte cada docente.
RENOMBRAR = {
    "Lengua Española y Literatura": "Lengua y Literatura Españolas",
    "Artes Visuales y Diseño": "Artes Visuales y Tecnología",
    "sin dpto.": OTROS,
}

INGLES_Y_ADQUISICION = "Inglés y Adquisición de Lenguas"
