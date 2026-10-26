import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./estilos/intranet.css";
import "./estilos/encuestas.css";
import { App } from "./App";
import { aplicarPaleta } from "./paleta";

// Colores de gráficos, indicadores y alertas como variables --en-* en :root, antes de pintar nada.
aplicarPaleta();

createRoot(document.getElementById("raiz")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
