import { fileURLToPath } from 'node:url';
import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

/** The runtime's own wire build, copied by `pnpm wire`, so nothing of the protocol is copied. */
const wire = fileURLToPath(new URL('./.runtime/packages/core/dist/wire.js', import.meta.url));

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: { alias: { '@memnox/core/wire': wire } },
  // Tauri serves the dev build on a fixed port and must see its own errors in the terminal.
  clearScreen: false,
  server: { port: 1420, strictPort: true },
  build: { target: 'es2022', outDir: 'dist' },
  test: { include: ['test/**/*.test.ts'] },
});
