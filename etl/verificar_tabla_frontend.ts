// Parte de etl/verificar_informes_2526.py: ejecuta las tablas del frontend sobre los informes que ha descargado el script
// (carpeta temporal): «Detalle por pregunta» del informe del profesor/a (src/data/tablaProfesor.ts) en
// tabla_frontend.json y, si están, las de tutoría y de servicios (src/data/tablasResumen.ts) en resumen_frontend.json.
// Uso (lo llama el script): npx vite-node etl/verificar_tabla_frontend.ts CARPETA
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { tablaProfesor } from "../src/data/tablaProfesor";
import { tablasServicio, tablasTutoria, type TablaResumen } from "../src/data/tablasResumen";
import type { InformeProfesor } from "../src/data/resultados";
import type { InformeServicio, InformeTutoria } from "../src/data/tutoriaServicios";

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

const resumen: Record<string, unknown> = {};
function anotar(clave: string, tablas: TablaResumen[]) {
  for (const t of tablas) {
    resumen[`${clave}|${t.clave}|columnas`] = t.columnas;
    t.filas.forEach((f) => f.valores.forEach((v, i) => { resumen[`${clave}|${t.clave}|${f.codigo}|${i}`] = v; }));
    if (t.referencia) resumen[`${clave}|${t.clave}|referencia`] = t.referencia.valor;
  }
}
if (existsSync(`${dir}/informes_tutoria.json`)) {
  const tut: Record<string, InformeTutoria> = JSON.parse(readFileSync(`${dir}/informes_tutoria.json`, "utf8"));
  for (const [clave, inf] of Object.entries(tut)) anotar(clave, tablasTutoria(inf));
}
if (existsSync(`${dir}/informes_servicio.json`)) {
  const srv: Record<string, InformeServicio> = JSON.parse(readFileSync(`${dir}/informes_servicio.json`, "utf8"));
  for (const [clave, inf] of Object.entries(srv)) anotar(clave, tablasServicio(inf));
}
writeFileSync(`${dir}/resumen_frontend.json`, JSON.stringify(resumen));
