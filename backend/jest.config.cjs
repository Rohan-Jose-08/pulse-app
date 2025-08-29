module.exports = {
  testEnvironment: 'node',
  transform: { '^.+\\.(ts|tsx)$': ['ts-jest', { tsconfig: 'tsconfig.json' }] },
  testMatch: ['**/tests/**/*.test.(ts|js)'],
  moduleFileExtensions: ['ts','js','json'],
  roots: ['<rootDir>/src','<rootDir>/tests'],
};
