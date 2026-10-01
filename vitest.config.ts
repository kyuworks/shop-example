import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  plugins: [react()],
  test: {
    // web/lib's pure functions are plain .test.ts; only components need .test.tsx.
    include: ['src/**/*.test.ts', 'web/**/*.test.ts', 'web/**/*.test.tsx'],
    exclude: ['src/**/*.integration.test.ts'],
  },
})
