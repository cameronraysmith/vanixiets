import { expect, test } from "../../e2e/fixtures";
import { expectTopologyText, pagePath, topologyNames, viewPath } from "../../e2e/fleet-topology";

// The fleet map's oracle against a served placement view missing one host:
// the first machine in fleet.json loses its <text>, and the unchanged oracle
// must reject it. check-negative-report.ts (mode `topology`) requires every
// attempt to fail as a product failure naming that host.
test("dropped host is rejected by the fleet topology oracle", async ({ page }) => {
  const [dropped] = topologyNames().machines;
  let intercepted = 0;
  await page.route(`**${viewPath("fleet")}*`, async (route) => {
    const response = await route.fetch();
    const body = (await response.text()).replaceAll(new RegExp(`<text\\b[^>]*>${dropped}</text>`, "g"), "");
    intercepted++;
    await route.fulfill({ response, body });
  });
  await page.goto(pagePath);
  try {
    await expectTopologyText(page);
  } finally {
    expect(intercepted, `${viewPath("fleet")} was never intercepted`).toBeGreaterThan(0);
  }
});
