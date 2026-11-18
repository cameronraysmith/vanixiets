import { defineConfig } from "@playwright/test";
import config from "./playwright.negative.config";

export default defineConfig(config, {
  testMatch: "fleet-topology.spec.ts",
});
