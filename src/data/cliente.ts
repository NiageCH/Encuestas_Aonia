// Única puerta al backend. Si el colegio decide poner su propio backend, se sustituye
// src/data/ sin tocar las vistas.

import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const clave = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

if (!url || !clave) {
  throw new Error("Faltan VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY (ver .env.example)");
}

export const supabase = createClient(url, clave, {
  auth: { persistSession: true, autoRefreshToken: true },
});

export const CURSO = "2025/26";
