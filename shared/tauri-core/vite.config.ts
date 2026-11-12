import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

/** The runtime's own wire build, kept in shared/wire and refreshed by `pnpm wire`, so nothing of the protocol is written by hand. */
const wire = fileURLToPath(new URL('../wire/wire.js', import.meta.url));

/** The pages beside this file, one per kind of window, by name. */
const root = fileURLToPath(new URL('.', import.meta.url));
const demo = fileURLToPath(new URL('../demo', import.meta.url));
const pages = Object.fromEntries(
  readdirSync(root)
    // The preview is for a designer's browser and never ships.
    .filter((file) => file.endsWith('.html') && file !== 'preview.html')
    .map((file) => [file.replace(/\.html$/, ''), fileURLToPath(new URL(`./${file}`, import.meta.url))]),
);

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: { alias: { '@memnox/core/wire': wire } },
  // Tauri serves the dev build on a fixed port and must see its own errors in the terminal.
  clearScreen: false,
  // The demo world lives in shared/demo beside this app, read by the Mac too, so the dev server may serve it.
  server: { port: 1420, strictPort: true, fs: { allow: [root, demo] } },
  // Every page at the root is built, so each window's page ships without being listed here by hand.
  build: { target: 'es2022', outDir: 'dist', rollupOptions: { input: pages } },
  test: { include: ['test/**/*.test.ts'] },
});
