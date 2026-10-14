import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./estilos/intranet.css";
import "./estilos/encuestas.css";
import { App } from "./App";

createRoot(document.getElementById("raiz")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
