/**
 * Firestore-emulator-backed integration tests — real trigger wiring, not
 * mocked Admin SDK. Run via `npm run test:integration` (wraps
 * `firebase emulators:exec`), not directly — these need the Firestore +
 * Functions emulators already running with FIRESTORE_EMULATOR_HOST set.
 */
module.exports = {
  testEnvironment: 'node',
  roots: ['<rootDir>/test/integration'],
  testTimeout: 20000,
  transform: {
    '^.+\\.ts$': ['ts-jest', { tsconfig: '<rootDir>/test/tsconfig.json' }],
  },
};
