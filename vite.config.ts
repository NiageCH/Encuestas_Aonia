import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { execSync } from "node:child_process";

// Versión de la web: el commit si hay git y, si no, la fecha de compilación. Se guarda con la sesión (src/data/sesion.ts).
function versionWeb(): string {
  try { return execSync("git rev-parse --short HEAD", { stdio: ["ignore", "pipe", "ignore"] }).toString().trim(); }
  catch { return new Date().toISOString(); }
}

// Sin peticiones externas: todo (fuente, logos, librerías) va en el bundle.
export default defineConfig({
  plugins: [react()],
  define: { __VERSION_WEB__: JSON.stringify(versionWeb()) },
  server: { host: "127.0.0.1", port: 5173, strictPort: true },
  build: { assetsInlineLimit: 0 },
});
