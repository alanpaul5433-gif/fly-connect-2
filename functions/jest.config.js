/** Unit tests only (mocked Admin SDK via firebase-functions-test, no emulator). */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testPathIgnorePatterns: ['/node_modules/', '<rootDir>/lib/'],
};
