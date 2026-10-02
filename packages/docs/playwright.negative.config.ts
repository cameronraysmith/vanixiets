import { defineConfig } from "@playwright/test";
import config from "./playwright.config";

// A separate suite: never weaken or mutate the production site or positive tests.
export default defineConfig(config, {
  testDir: "./tests/negative-control",
  testMatch: "reader-journey.spec.ts",
  // Inherit the suite's retries: a retry can only add failed attempts to a
  // deterministic defect, and check-negative-report.ts requires every one to fail.
  workers: 1,
  expect: { timeout: 1000 },
  projects: config.projects?.filter((project) => project.name === "chromium"),
});
