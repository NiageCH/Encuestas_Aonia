// Única puerta al backend. Si el colegio decide poner su propio backend, se sustituye
// src/data/ sin tocar las vistas.

import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const clave = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

if (!url || !clave) {
  throw new Error("Faltan VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY (ver .env.example)");
}

// Los enlaces de invitación y de recuperación de contraseña llegan con los tokens en el «#»
// de la dirección (type=invite o type=recovery). Se lee aquí, antes de que el cliente los
// consuma, para pedir la contraseña nueva al entrar.
export const tipoEnlace: "invite" | "recovery" | null = (() => {
  const tipo = new URLSearchParams(window.location.hash.replace(/^#/, "")).get("type");
  return tipo === "invite" || tipo === "recovery" ? tipo : null;
})();

export const supabase = createClient(url, clave, {
  auth: { persistSession: true, autoRefreshToken: true },
});

export const CURSO = "2025/26";
