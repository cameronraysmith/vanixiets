import os from "node:os";
import { defineConfig, devices } from "@playwright/test";

const allProjects = {
  chromium: { name: "chromium", use: { ...devices["Desktop Chrome"] } },
  firefox: { name: "firefox", use: { ...devices["Desktop Firefox"] } },
  webkit: { name: "webkit", use: { ...devices["Desktop Safari"] } },
} as const;

type ProjectName = keyof typeof allProjects;

/**
 * Browser selection is explicit, never inferred from CI.
 *
 * PLAYWRIGHT_PROJECTS is a comma-separated subset of chromium,firefox,webkit.
 * Unset means all three: the hermetic nix check (which sets CI=true for
 * retries/reporter/webServer) must exercise every engine, and a genuinely
 * constrained CI runner narrows itself by setting the variable.
 */
function selectedProjects() {
  const requested = (process.env.PLAYWRIGHT_PROJECTS ?? "")
    .split(",")
    .map((name) => name.trim())
    .filter(Boolean);
  if (requested.length === 0) return Object.values(allProjects);
  const unknown = requested.filter((name) => !(name in allProjects));
  if (unknown.length > 0) {
    throw new Error(
      `PLAYWRIGHT_PROJECTS names unknown browsers: ${unknown.join(", ")}. ` +
        `Valid values: ${Object.keys(allProjects).join(", ")}.`,
    );
  }
  return requested.map((name) => allProjects[name as ProjectName]);
}

/**
 * Worker count. PLAYWRIGHT_WORKERS wins when set so the nix check can size
 * itself to the builder it runs on; otherwise use every core locally and a
 * conservative 3 under an unconfigured CI.
 */
function workerCount() {
  const explicit = process.env.PLAYWRIGHT_WORKERS;
  if (explicit) {
    const parsed = Number.parseInt(explicit, 10);
    if (!Number.isInteger(parsed) || parsed < 1) {
      throw new Error(`PLAYWRIGHT_WORKERS must be a positive integer, got ${explicit}`);
    }
    return parsed;
  }
  return process.env.CI ? 3 : os.cpus().length;
}

/**
 * Playwright configuration for E2E testing
 * @see https://playwright.dev/docs/test-configuration
 */
export default defineConfig({
  // Test directory
  testDir: "./e2e",

  // Run tests in files in parallel
  fullyParallel: true,

  // Fail the build on CI if you accidentally left test.only in the source code
  forbidOnly: Boolean(process.env.CI),

  // Retry on CI only
  retries: process.env.CI ? 2 : 0,

  // Explicit PLAYWRIGHT_WORKERS wins; see workerCount() above.
  workers: workerCount(),

  // Reporter configuration
  reporter: process.env.CI
    ? [
        ["html", { outputFolder: "playwright-report", open: "never" }],
        ["json", { outputFile: "playwright-report/results.json" }],
        ["github"],
      ]
    : [["list"], ["html", { outputFolder: "playwright-report", open: "never" }]],

  // Increase assertion timeout on CI where Vite cold-start compilation is slower
  expect: {
    timeout: process.env.CI ? 15000 : 5000,
  },

  // Shared settings for all projects
  use: {
    // Base URL for page.goto() calls
    baseURL: process.env.BASE_URL ?? "http://localhost:4321",

    // Collect trace when retrying the failed test
    trace: "on-first-retry",

    // Screenshot on failure
    screenshot: "only-on-failure",

    // Video on failure
    video: "retain-on-failure",
  },

  // Configure projects for major browsers; see selectedProjects() above.
  projects: selectedProjects(),

  // Run local dev server before starting tests.
  // In CI: serve pre-built static output (faster, matches production artifact).
  // In dev: astro dev server (supports HMR, serves from source).
  webServer: {
    command: process.env.CI ? "bun run preview:ci" : "bun run dev",
    url: "http://localhost:4321",
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
  },
});
