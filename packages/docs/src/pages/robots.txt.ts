import type { APIRoute } from "astro";

export const GET: APIRoute = ({ site }) => {
  if (!site) throw new Error("robots.txt needs `site` in astro.config.ts for its Sitemap line");
  return new Response(
    [
      `# Documentation for LLMs and agents: ${new URL("/llms.txt", site).href}`,
      "# Each page is also served as Markdown at its path with .md in place of the trailing slash.",
      `# Agent Skills discovery index: ${new URL("/.well-known/agent-skills/index.json", site).href}`,
      "User-agent: *",
      "Allow: /",
      "",
      `Sitemap: ${new URL("/sitemap-index.xml", site).href}`,
      "",
    ].join("\n"),
    { headers: { "Content-Type": "text/plain; charset=utf-8" } },
  );
};
