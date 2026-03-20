// vitest.config.base.ts — Base Vitest configuration
// Managed by ai-dev-lifecycle (https://github.com/goeke-m/ai-dev-lifecycle)
//
// Usage in a consuming project — merge with your project-specific config:
//
//   import { mergeConfig } from 'vitest/config';
//   import baseConfig from './path/to/vitest.config.base';
//
//   export default mergeConfig(baseConfig, {
//     test: {
//       include: ['src/**/*.{test,spec}.ts'],
//       setupFiles: ['./src/test/setup.ts'],
//     },
//   });

import { defineConfig } from 'vitest/config';
import { fileURLToPath } from 'node:url';

export default defineConfig({
  test: {
    // ── Test discovery ─────────────────────────────────────────────────────────
    include: ['src/**/*.{test,spec}.{ts,tsx,js,jsx}', 'tests/**/*.{test,spec}.{ts,tsx,js,jsx}'],
    exclude: [
      '**/node_modules/**',
      '**/dist/**',
      '**/build/**',
      '**/coverage/**',
      '**/.next/**',
      '**/e2e/**',
    ],

    // ── Environment ───────────────────────────────────────────────────────────
    // Use 'node' for backend projects, 'jsdom' or 'happy-dom' for frontend.
    // Override in project config.
    environment: 'node',

    // ── Globals ───────────────────────────────────────────────────────────────
    // Set to true to avoid importing describe/it/expect in every test file.
    // If true, also add "types": ["vitest/globals"] to tsconfig.
    globals: false,

    // ── Timeout ───────────────────────────────────────────────────────────────
    // Default per-test timeout (ms). Individual tests can override with
    // test('name', { timeout: 10000 }, async () => { ... })
    testTimeout: 10000,

    // Hook timeout (ms) — for beforeAll/afterAll that do expensive setup
    hookTimeout: 30000,

    // ── Retry ─────────────────────────────────────────────────────────────────
    // Do not retry flaky tests — fix them instead.
    retry: 0,

    // ── Reporter ──────────────────────────────────────────────────────────────
    // Use 'verbose' locally, 'dot' or 'github-actions' in CI.
    reporter: process.env.CI ? ['github-actions', 'json'] : ['verbose'],

    // Output dir for JSON / HTML reporter
    outputFile: {
      json: './test-results/results.json',
    },

    // ── Coverage ──────────────────────────────────────────────────────────────
    coverage: {
      // Coverage provider: 'v8' (fast, native) or 'istanbul' (more accurate)
      provider: 'v8',

      // Whether to enable coverage when running `vitest run`
      // Use `vitest run --coverage` to enable, or set enabled: true here.
      enabled: false,

      // Files to include in coverage (even if not imported by tests)
      include: ['src/**/*.{ts,tsx,js,jsx}'],

      // Exclude from coverage
      exclude: [
        'src/**/*.{test,spec}.{ts,tsx,js,jsx}',
        'src/**/__tests__/**',
        'src/**/index.{ts,js}', // barrel files — typically just re-exports
        'src/**/types.ts',
        'src/**/types/**',
        'src/**/*.d.ts',
        'src/**/generated/**',
        '**/node_modules/**',
        '**/dist/**',
      ],

      // Output directory for coverage reports
      reportsDirectory: './coverage',

      // Report formats
      reporter: ['text', 'text-summary', 'cobertura', 'html', 'lcov'],

      // Coverage thresholds — fail the run if not met
      thresholds: {
        lines: 80,
        branches: 75,
        functions: 80,
        statements: 80,
      },

      // Watermarks control the colour (green/yellow/red) in the text report
      watermarks: {
        lines: [80, 95],
        functions: [80, 95],
        branches: [75, 90],
        statements: [80, 95],
      },

      // Whether to show files with zero coverage
      all: true,

      // Skip coverage for files that are only type imports
      ignoreEmptyLines: true,
    },

    // ── Type checking ─────────────────────────────────────────────────────────
    // Run tsc alongside tests (slower but catches type errors without a
    // separate typecheck step)
    typecheck: {
      enabled: false, // Enable if you want in-test type checking
      tsconfig: './tsconfig.json',
    },

    // ── Pool ──────────────────────────────────────────────────────────────────
    // 'threads' — Worker threads (default, fastest)
    // 'forks'   — Child processes (better for tests that mutate global state)
    // 'vmForks' — Isolated VM context per file (most isolated, slowest)
    pool: 'threads',

    poolOptions: {
      threads: {
        // Limit parallelism to avoid resource contention in CI
        maxThreads: process.env.CI ? 2 : undefined,
        minThreads: 1,
        isolate: true,
      },
    },

    // ── Watch mode ────────────────────────────────────────────────────────────
    // Only re-run tests related to changed files
    watchExclude: ['**/node_modules/**', '**/dist/**', '**/coverage/**'],

    // ── Misc ──────────────────────────────────────────────────────────────────
    // Fail on console.error calls (useful to catch unexpected errors in tests)
    // onConsoleLog: (log, type) => type === 'stderr' ? false : undefined,

    // Print a test duration warning for slow tests (ms)
    slowTestThreshold: 300,
  },

  // ── Resolve ───────────────────────────────────────────────────────────────
  resolve: {
    alias: {
      // Override in project config with your path aliases, e.g.:
      // '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
});
