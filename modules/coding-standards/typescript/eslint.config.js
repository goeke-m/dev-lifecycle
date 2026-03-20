// eslint.config.js — Flat ESLint config (ESLint v9)
// Managed by ai-dev-lifecycle (https://github.com/goeke-m/ai-dev-lifecycle)
// Extend this in consuming projects:
//   import baseConfig from './eslint.config.base.js';
//   export default [...baseConfig, { /* project-specific overrides */ }];

import js from '@eslint/js';
import tsEslint from 'typescript-eslint';
import prettierConfig from 'eslint-config-prettier';
import prettierPlugin from 'eslint-plugin-prettier';
import globals from 'globals';

export default tsEslint.config(
  // ── Ignored paths ───────────────────────────────────────────────────────────
  {
    ignores: [
      '**/dist/**',
      '**/build/**',
      '**/coverage/**',
      '**/.next/**',
      '**/node_modules/**',
      '**/*.min.js',
      '**/*.d.ts',
      '**/generated/**',
    ],
  },

  // ── Base JS rules ────────────────────────────────────────────────────────────
  js.configs.recommended,

  // ── TypeScript recommended rules ─────────────────────────────────────────────
  ...tsEslint.configs.recommendedTypeChecked,
  ...tsEslint.configs.stylisticTypeChecked,

  // ── Global settings for TypeScript files ─────────────────────────────────────
  {
    files: ['**/*.{ts,tsx,mts,cts}'],
    languageOptions: {
      globals: {
        ...globals.node,
        ...globals.es2022,
      },
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      // ── TypeScript-specific ─────────────────────────────────────────────────

      // Disallow `any` — use `unknown` when the type is genuinely unknown
      '@typescript-eslint/no-explicit-any': 'error',

      // Require explicit return types on exported functions
      '@typescript-eslint/explicit-module-boundary-types': 'warn',

      // Prefer `unknown` over `any` in catch clauses
      '@typescript-eslint/use-unknown-in-catch-callback-variable': 'error',

      // Require await in async functions (catches accidental non-async)
      '@typescript-eslint/require-await': 'error',

      // Prefer async/await over Promise chains
      '@typescript-eslint/prefer-promise-reject-errors': 'error',
      '@typescript-eslint/return-await': ['error', 'in-try-catch'],

      // No floating (unhandled) promises
      '@typescript-eslint/no-floating-promises': 'error',

      // No misused promises (e.g., in boolean contexts)
      '@typescript-eslint/no-misused-promises': [
        'error',
        {
          checksVoidReturn: {
            arguments: false, // Allow passing async callbacks to event handlers
          },
        },
      ],

      // Consistent type assertions
      '@typescript-eslint/consistent-type-assertions': [
        'error',
        { assertionStyle: 'as', objectLiteralTypeAssertions: 'never' },
      ],

      // Prefer type imports for type-only imports
      '@typescript-eslint/consistent-type-imports': [
        'error',
        { prefer: 'type-imports', fixStyle: 'inline-type-imports' },
      ],

      // No unnecessary type assertions
      '@typescript-eslint/no-unnecessary-type-assertion': 'error',

      // No non-null assertions with optional chain (obj!.prop is redundant if using ?.)
      '@typescript-eslint/no-non-null-assertion': 'warn',

      // Prefer nullish coalescing over || for nullable values
      '@typescript-eslint/prefer-nullish-coalescing': [
        'error',
        { ignorePrimitives: { boolean: true } },
      ],

      // Prefer optional chain over && chains
      '@typescript-eslint/prefer-optional-chain': 'error',

      // No unused variables (TypeScript handles this better than the base rule)
      'no-unused-vars': 'off',
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          args: 'all',
          argsIgnorePattern: '^_',
          caughtErrors: 'all',
          caughtErrorsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          ignoreRestSiblings: true,
        },
      ],

      // Require consistent member ordering
      '@typescript-eslint/member-ordering': [
        'warn',
        {
          default: [
            'public-static-field',
            'protected-static-field',
            'private-static-field',
            'public-instance-field',
            'protected-instance-field',
            'private-instance-field',
            'constructor',
            'public-static-method',
            'protected-static-method',
            'private-static-method',
            'public-instance-method',
            'protected-instance-method',
            'private-instance-method',
          ],
        },
      ],

      // Prefer readonly for properties that are never reassigned
      '@typescript-eslint/prefer-readonly': 'warn',

      // No use before define (but allow function declarations — hoisting is fine)
      'no-use-before-define': 'off',
      '@typescript-eslint/no-use-before-define': [
        'error',
        { functions: false, classes: true, variables: true },
      ],

      // ── General best practices ───────────────────────────────────────────────

      // Disallow console.log in production code (use a logger)
      'no-console': ['warn', { allow: ['warn', 'error', 'info'] }],

      // Prefer const
      'prefer-const': 'error',

      // Disallow var
      'no-var': 'error',

      // Require === instead of ==
      eqeqeq: ['error', 'always', { null: 'ignore' }],

      // No duplicate imports
      'no-duplicate-imports': 'error',

      // Consistent arrow function body style
      'arrow-body-style': ['warn', 'as-needed'],

      // Object shorthand
      'object-shorthand': ['error', 'always'],

      // Disallow throwing non-Error objects
      'no-throw-literal': 'off',
      '@typescript-eslint/only-throw-error': 'error',

      // Enforce import ordering (manual alphabetical sort)
      'sort-imports': [
        'warn',
        {
          ignoreCase: false,
          ignoreDeclarationSort: true, // handled by prettier
          ignoreMemberSort: false,
          memberSyntaxSortOrder: ['none', 'all', 'multiple', 'single'],
        },
      ],
    },
  },

  // ── JavaScript files (no type-aware rules) ───────────────────────────────────
  {
    files: ['**/*.{js,jsx,mjs,cjs}'],
    ...tsEslint.configs.disableTypeChecked,
    rules: {
      'no-unused-vars': ['error', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
    },
  },

  // ── Test files — relaxed rules ───────────────────────────────────────────────
  {
    files: ['**/*.{test,spec}.{ts,tsx,js,jsx}', '**/__tests__/**/*.{ts,tsx,js,jsx}'],
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
      '@typescript-eslint/explicit-module-boundary-types': 'off',
      'no-console': 'off',
    },
  },

  // ── Prettier integration (must be last to disable conflicting rules) ──────────
  prettierConfig,
  {
    plugins: {
      prettier: prettierPlugin,
    },
    rules: {
      'prettier/prettier': 'error',
    },
  },
);
