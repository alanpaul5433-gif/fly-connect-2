/**
 * Firestore security-rule tests. These load firestore.rules into the Firestore
 * emulator and assert what each caller may read/write — the layer that catches
 * a rule which is too permissive (or too strict to satisfy a real query).
 *
 * Run via `npm run test:rules` (wraps `firebase emulators:exec`), not directly.
 */
module.exports = {
  testEnvironment: 'node',
  roots: ['<rootDir>/test/rules'],
  testTimeout: 20000,
  transform: {
    '^.+\\.ts$': ['ts-jest', { tsconfig: '<rootDir>/test/tsconfig.json' }],
  },
};
