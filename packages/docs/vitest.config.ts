/// <reference types="vitest/config" />
import { getViteConfig } from "astro/config";

// Skip Cloudflare adapter during tests: @cloudflare/vite-plugin (bundled in
// adapter v13) rejects Vitest's SSR resolve.external for Node built-ins.
// AstroContainer does not require a deployment adapter.
process.env.VITEST = "true";

export default getViteConfig({
  test: {
    // Test environment
    environment: "node",

    // Global test APIs (describe, it, expect) without imports
    globals: true,

    // Test file patterns
    include: ["src/**/*.{test,spec}.{ts,tsx}", "tests/**/*.{test,spec}.{ts,tsx}"],

    // Files to exclude from test discovery
    exclude: ["node_modules", "dist", ".astro", "e2e"],

    // Coverage configuration
    coverage: {
      provider: "v8",
      reporter: ["text", "json", "html", "lcov"],
      exclude: [
        "node_modules",
        "dist",
        ".astro",
        "e2e",
        "**/*.config.{ts,js,mjs}",
        "**/*.d.ts",
        "**/env.d.ts",
        "tests/**",
        "src/**/*.{test,spec}.{ts,tsx}",
      ],
      reportsDirectory: "./coverage",
    },

    // Type checking
    typecheck: {
      enabled: false,
    },

    // Fail tests on console errors
    onConsoleLog: (log: string): false | undefined => {
      if (log.includes("error")) {
        return false;
      }
    },
  },
});
