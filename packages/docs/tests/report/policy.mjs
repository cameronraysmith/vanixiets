// Independent expected inventory: removing a spec must not silently reduce
// coverage. Update this list deliberately when adding/removing a reader check.
export const requiredCases = {
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
};
