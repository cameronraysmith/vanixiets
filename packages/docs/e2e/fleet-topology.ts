import { readFileSync } from "node:fs";
import { expect, type Page } from "@playwright/test";

/**
 * The fleet map's browser oracle (openspec change diagram-fleet-topology,
 * D13). Its expectations come from the committed fleet.json, never from a
 * hand list, so they follow the map: every machine must be the text of a
 * `<text>` element in the served placement view, and every fleet network and
 * each of its members must be in the served network view. The images are
 * `<img>` elements, whose words are not in the page's DOM, so the oracle
 * fetches the SVG the browser decodes and parses it in the page.
 */

const fleetJson = new URL("../diagrams/topology/fleet.json", import.meta.url);

export const views = ["fleet", "network"] as const;
export type View = (typeof views)[number];

export const viewPath = (view: View) => `/diagrams/topology-${view}.svg`;

export function topologyNames(): { machines: string[]; networks: Record<string, string[]> } {
  const entries: unknown = JSON.parse(readFileSync(fleetJson, "utf8"));
  if (!entries || typeof entries !== "object") throw new Error("fleet.json is not an object");
  const machines: string[] = [];
  const networks: Record<string, string[]> = {};
  for (const [key, value] of Object.entries(entries)) {
    const [kind, name] = key.split("/", 2);
    if (kind === "machine") machines.push(name);
    if (kind === "network") {
      if (!value || typeof value !== "object" || !("members" in value)) {
        throw new Error(`fleet.json ${key} has no members`);
      }
      const { members } = value;
      if (!members || typeof members !== "object") throw new Error(`fleet.json ${key} members is not an object`);
      networks[name] = Object.keys(members);
    }
  }
  expect(machines.length, "fleet.json lists no machines").toBeGreaterThan(0);
  expect(Object.keys(networks).length, "fleet.json lists no fleet networks").toBeGreaterThan(0);
  return { machines, networks };
}

export const pagePath = "/concepts/fleet-topology/";

// Fetched from inside the page, so the request takes the same path as the
// <img> (and the negative control's page.route interception applies);
// page.request would bypass both.
async function svgTexts(page: Page, view: View): Promise<string[]> {
  const { status, texts } = await page.evaluate(async (path) => {
    const response = await fetch(path);
    const svg = await response.text();
    const doc = new DOMParser().parseFromString(svg, "image/svg+xml");
    const parses = svg.length > 0 && doc.getElementsByTagName("parsererror").length === 0;
    return {
      status: response.status,
      texts: parses ? Array.from(doc.getElementsByTagName("text"), (text) => (text.textContent ?? "").trim()) : null,
    };
  }, viewPath(view));
  expect(status, `${viewPath(view)} status`).toBe(200);
  expect(texts, `${viewPath(view)} is empty or does not parse as SVG`).not.toBeNull();
  return texts ?? [];
}

export async function expectTopologyText(page: Page) {
  const { machines, networks } = topologyNames();
  if (!page.url().includes(pagePath)) await page.goto(pagePath);
  const fleet = await svgTexts(page, "fleet");
  for (const machine of machines) {
    expect(fleet, `host ${machine} is not a <text> in ${viewPath("fleet")}`).toContain(machine);
  }
  const network = await svgTexts(page, "network");
  for (const [name, members] of Object.entries(networks)) {
    expect(network, `fleet network ${name} is not a <text> in ${viewPath("network")}`).toContain(name);
    for (const member of members) {
      expect(network, `member ${member} of ${name} is not a <text> in ${viewPath("network")}`).toContain(member);
    }
  }
}
