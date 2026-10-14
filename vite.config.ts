import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Sin peticiones externas: todo (fuente, logos, librerías) va en el bundle.
export default defineConfig({
  plugins: [react()],
  server: { host: "127.0.0.1", port: 5173, strictPort: true },
  build: { assetsInlineLimit: 0 },
});
