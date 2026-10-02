// Independent expected inventory: removing a spec must not silently reduce
// coverage. Update this list deliberately when adding/removing a reader check.
export const requiredCases: Readonly<Record<string, readonly string[]>> = {
  "playwright.config.ts": [
    "homepage.spec.ts::has correct title and heading",
    "homepage.spec.ts::has accessible links",
    "homepage.spec.ts::navigates to getting started guide",
    "homepage.spec.ts::is responsive on mobile",
    "homepage.spec.ts::loads without console errors",
    "homepage.spec.ts::hero image loads successfully",
    "documentation-pages.spec.ts::has sidebar navigation on getting started guide page",
    "documentation-pages.spec.ts::sidebar contains configured navigation items",
    "documentation-pages.spec.ts::has table of contents on desktop",
    "reader-journey.spec.ts::reader finds bootstrap prerequisites and a guided reading path",
  ],
  "playwright.negative.config.ts": ["reader-journey.spec.ts::damaged guide is rejected by the real reader journey"],
  "playwright.action-negative.config.ts": [
    "removed-link.spec.ts::removed homepage link is rejected by the real reader journey",
  ],
};

export type Engine = "chromium" | "firefox" | "webkit";

// Independent of PLAYWRIGHT_PROJECTS and of discovery: the producer cannot
// redefine coverage by narrowing its own configuration and metadata together.
// Darwin Firefox cannot launch in the Nix build environment; the package
// documents the native-build experiments behind this explicit exception.
export const requiredEngines: Readonly<Record<string, readonly Engine[]>> = {
  "aarch64-darwin": ["chromium", "webkit"],
  "x86_64-darwin": ["chromium", "webkit"],
  "x86_64-linux": ["chromium", "firefox", "webkit"],
  "aarch64-linux": ["chromium", "firefox", "webkit"],
};

export function requiredProjects(system: string, config: string): readonly Engine[] | undefined {
  if (!Object.hasOwn(requiredEngines, system)) return undefined;
  if (config === "playwright.negative.config.ts" || config === "playwright.action-negative.config.ts") {
    return ["chromium"];
  }
  return config === "playwright.config.ts" ? requiredEngines[system] : undefined;
}
