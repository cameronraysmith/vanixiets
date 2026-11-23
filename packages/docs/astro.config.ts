import cloudflare from "@astrojs/cloudflare";
import starlight from "@astrojs/starlight";
import starlightLinksValidator from "starlight-links-validator";
import { starlightKatex } from "starlight-katex";
import starlightLlmsTxt from "starlight-llms-txt";
import starlightMdTxt from "starlight-md-txt";
import { unified } from "@astrojs/markdown-remark";
import { defineConfig } from "astro/config";
import justGrammar from "./src/grammars/just.tmLanguage.json";
// ROLLDOWN INTEGRATION (DISABLED) - Uncomment when re-enabling (see ROLLDOWN.md)
// import * as vite from "vite";

// https://astro.build/config
export default defineConfig({
  site: "https://infra.cameronraysmith.net",
  integrations: [
    starlight({
      title: "vanixiets",
      prerender: true,
      plugins: [
        ...(process.env.CHECK_LINKS ? [starlightLinksValidator({ errorOnRelativeLinks: false })] : []),
        starlightKatex(),
        starlightLlmsTxt({
          description:
            "vanixiets is a Nix flake for a multi-machine fleet of NixOS, nix-darwin and home-manager configurations, built from aspect-based deferred flake-parts modules and deployed with clan; it also publishes a marketplace of agent skills.",
          details: [
            "Entry points:",
            "",
            "- [Source repository](https://github.com/cameronraysmith/vanixiets): the flake, its modules and the agent skills under `modules/home/ai/plugins/`",
            "- [Consuming marketplace plugins](https://infra.cameronraysmith.net/guides/consuming-marketplace-plugins.md): install routes for the repository's agent-skill marketplace (apm, Claude Code, the Claude desktop app, the skills CLI)",
            "- [Getting started](https://infra.cameronraysmith.net/guides/getting-started.md): the guides' starting point",
            "",
            "Every page is also served as Markdown: append `.md` to its path without the trailing slash, for example `/guides/getting-started.md`, and `/index.md` for the home page.",
          ].join("\n"),
          demote: ["development/traceability/satisfaction"],
          exclude: ["development/**"],
          // The default HTML-to-Markdown round trip flattens KaTeX output to its
          // visual text (`\bigsqcup_{i=1}^{n}` becomes `i=1⨆n`) and drops the TeX;
          // the source keeps every formula as written.
          rawContent: true,
        }),
        starlightMdTxt({ alternateLink: true, absoluteLinks: true }),
      ],
      customCss: ["./src/fonts/font-face.css", "./src/styles/custom.css"],
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/cameronraysmith/vanixiets",
        },
      ],
      expressiveCode: {
        shiki: {
          langs: [justGrammar],
        },
      },
      sidebar: [
        {
          label: "Tutorials",
          items: [{ autogenerate: { directory: "tutorials" } }],
        },
        {
          label: "Guides",
          items: [{ autogenerate: { directory: "guides" } }],
        },
        {
          label: "Concepts",
          collapsed: true,
          items: [{ autogenerate: { directory: "concepts", collapsed: true } }],
        },
        {
          label: "Reference",
          collapsed: true,
          items: [{ autogenerate: { directory: "reference", collapsed: true } }],
        },
        {
          label: "Development",
          collapsed: true,
          items: [
            { label: "Contents", link: "/development/" },
            {
              label: "Context",
              collapsed: true,
              items: [{ autogenerate: { directory: "development/context", collapsed: true } }],
            },
            {
              label: "Requirements",
              collapsed: true,
              items: [{ autogenerate: { directory: "development/requirements", collapsed: true } }],
            },
            {
              label: "Architecture",
              collapsed: true,
              items: [
                { label: "Contents", link: "/development/architecture/" },
                { label: "Architecture", link: "/development/architecture/architecture" },
                {
                  label: "Decision records",
                  collapsed: true,
                  items: [{ autogenerate: { directory: "development/architecture/adrs", collapsed: true } }],
                },
              ],
            },
            {
              label: "Traceability",
              collapsed: true,
              items: [{ autogenerate: { directory: "development/traceability", collapsed: true } }],
            },
          ],
        },
        {
          label: "About",
          collapsed: true,
          items: [
            {
              label: "Contributing",
              collapsed: true,
              items: [{ autogenerate: { directory: "about/contributing", collapsed: true } }],
            },
            { label: "Credits", link: "/about/credits" },
          ],
        },
      ],
    }),
  ],

  adapter: process.env.VITEST
    ? undefined
    : cloudflare({
        // Use 'passthrough' to serve images directly without Cloudflare Image Resizing
        // The 'cloudflare' option requires the Image Resizing subscription
        // Reference: https://docs.astro.build/en/guides/integrations-guide/cloudflare/#imageservice
        imageService: "passthrough",
        // Use Node-based prerenderer instead of workerd preview server to skip
        // miniflare/workerd glibc-binary execution in the nix build sandbox.
        // Reference: @astrojs/cloudflare src/prerenderer.ts (workerd path gated
        // on prerenderEnvironment === 'workerd').
        prerenderEnvironment: "node",
        // Report builds serve `astro preview` concurrently on a shared darwin
        // host network. Unset, @cloudflare/vite-plugin probes upward from 9229
        // for a workerd inspector port, so concurrent builds race between the
        // probe and the bind (EADDRINUSE). Nothing in a report build attaches
        // a debugger, so the nix e2e-report derivation turns it off; `false`
        // makes the plugin pass no inspectorPort to miniflare. Local dev keeps
        // the default inspector.
        ...(process.env.DOCS_DISABLE_WORKER_INSPECTOR === "1" ? { inspectorPort: false as const } : {}),
      }),

  vite: {
    ssr: {
      optimizeDeps: {
        exclude: ["virtual:starlight/*"],
      },
    },
  },

  markdown: {
    processor: unified(),
    syntaxHighlight: {
      type: "shiki",
      // math is excluded for KaTeX compatibility
      excludeLangs: ["math"],
    },
  },

  /* ROLLDOWN INTEGRATION (DISABLED - Cloudflare Workers Incompatibility)
   *
   * Status: Disabled due to runtime error in Cloudflare Workers
   * Issue: https://github.com/cloudflare/workers-sdk/issues/9415
   * Fix PR: https://github.com/cloudflare/workers-sdk/pull/9891
   *
   * Problem: Rolldown generates createRequire(import.meta.url) which fails
   * in Cloudflare Workers where import.meta.url is undefined.
   *
   * The fix (platform: "neutral") only works with @cloudflare/vite-plugin,
   * not with @astrojs/cloudflare adapter used in this project.
   *
   * TO RE-ENABLE (when compatibility is resolved):
   * 1. Uncomment the vite import above
   * 2. Add to package.json devDependencies:
   *    "vite": "npm:rolldown-vite@latest"
   * 3. Add to package.json root:
   *    "overrides": { "vite": "npm:rolldown-vite@latest" }
   * 4. Run: bun install
   * 5. Uncomment the vite config below
   * 6. Test: bun run build && bun run preview
   *
   * See ROLLDOWN.md for complete documentation and alternative approaches.
   */

  // vite: {
  //   // Attempted fix for rolldown-vite + Cloudflare Workers compatibility
  //   // https://github.com/cloudflare/workers-sdk/pull/9891
  //   ...("rolldownVersion" in vite
  //     ? {
  //         optimizeDeps: {
  //           esbuildOptions: {
  //             platform: "neutral",
  //           },
  //         },
  //       }
  //     : {}),
  // },
});
