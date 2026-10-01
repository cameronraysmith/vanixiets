import { defineConfig } from "@playwright/test";
import config from "./playwright.config";

// A separate suite: never weaken or mutate the production site or positive tests.
export default defineConfig(config, {
  testDir: "./tests/negative-control",
  testMatch: "reader-journey.spec.ts",
  retries: 0,
  workers: 1,
  expect: { timeout: 1000 },
  projects: config.projects?.filter((project) => project.name === "chromium"),
});
