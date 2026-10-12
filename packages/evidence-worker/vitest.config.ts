import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

// Tests run inside workerd against wrangler.jsonc's bindings, with the R2
// bucket simulated locally by Miniflare and seeded by each test.
export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
    }),
  ],
  test: {
    // Vitest 5 enables this by default at the workspace root's node_modules,
    // and @cloudflare/vitest-plugin's runner in workerd then fails to read the
    // entries (ENOENT). Every check build starts from an empty tree, so the
    // cache has nothing to reuse anyway.
    fsModuleCache: false,
  },
});
