/// <reference types="vite/client" />

declare const __VERSION_WEB__: string;

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL: string;
  readonly VITE_SUPABASE_ANON_KEY: string;
  readonly VITE_AVISO_VALIDACION?: string;
}
