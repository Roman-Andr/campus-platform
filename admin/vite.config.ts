import react from '@vitejs/plugin-react';
import { defineConfig, loadEnv } from 'vite';
import { configDefaults } from 'vitest/config';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  return {
    plugins: [react()],
    build: {
      // react-admin with MUI is ~850 kB minified; the panel is a desktop-only
      // internal tool, so one vendor bundle is fine until sections are lazy-loaded.
      chunkSizeWarningLimit: 1000,
    },
    server: {
      proxy: {
        '/api': { target: env.API_PROXY_TARGET || 'http://localhost:8000', changeOrigin: true },
      },
    },
    test: {
      globals: true,
      environment: 'jsdom',
      setupFiles: ['./src/test/setup.ts'],
      exclude: [...configDefaults.exclude, 'e2e/**'],
      coverage: {
        provider: 'v8',
        include: ['src/**/*.{ts,tsx}'],
        exclude: ['src/main.tsx', 'src/test/**', 'src/**/*.test.{ts,tsx}'],
        reporter: ['text', 'html', 'lcov'],
        thresholds: { lines: 80, branches: 80, functions: 80, statements: 80 },
      },
    },
  };
});
