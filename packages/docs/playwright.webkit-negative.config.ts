import { defineConfig } from "@playwright/test";
import config from "./playwright.config";

// The damaged-guide negative control on WebKit: a completed WebKit product
// failure must keep a trace and a non-empty PNG screenshot on every system.
export default defineConfig(config, {
  testDir: "./tests/negative-control",
  testMatch: "reader-journey.spec.ts",
  // Inherit the suite's retries, like the other negative controls.
  workers: 1,
  expect: { timeout: 1000 },
  projects: config.projects?.filter((project) => project.name === "webkit"),
});
