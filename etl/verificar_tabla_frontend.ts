// Parte de etl/verificar_informes_2526.py: ejecuta la tabla «Detalle por pregunta» del frontend (src/data/tablaProfesor.ts)
// sobre los informes que ha descargado el script (carpeta temporal) y deja cada celda en tabla_frontend.json.
// Uso (lo llama el script): npx vite-node etl/verificar_tabla_frontend.ts CARPETA
import { readFileSync, writeFileSync } from "node:fs";
import { tablaProfesor } from "../src/data/tablaProfesor";
import type { InformeProfesor } from "../src/data/resultados";

const dir = process.argv[2];
const informes: Record<string, InformeProfesor> = JSON.parse(readFileSync(`${dir}/informes_profesor.json`, "utf8"));
const salida: Record<string, unknown> = {};
for (const [clave, informe] of Object.entries(informes)) {
  const tabla = tablaProfesor(informe);
  tabla.filas.forEach((fila) => tabla.columnas.forEach((col, i) => {
    salida[`${clave}|${fila.codigo}|${col.tipo}|${"etapa" in col ? col.etapa : ""}`] = fila.valores[i];
  }));
}
writeFileSync(`${dir}/tabla_frontend.json`, JSON.stringify(salida));
