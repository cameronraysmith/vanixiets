# Playwright CLI

This packages the agent-facing `@playwright/cli`, not the `playwright` test runner or Playwright MCP.
The pinned `halfwhey/nix-playwright-nightly` input supplies the CLI dependency lock and matching browser revisions.
The CLI release is selected in `package.nix`; changing it requires a matching pin in that input.
The documentation site's `playwright-web-flake` input and npm dependencies remain independent.

## Runtime

Chromium, its headless shell, and ffmpeg are bundled by default.
`pkgs.playwright-cli.override { withFirefox = true; withWebkit = true; }` opts into the provider's larger browser set; the default smoke test does not establish those engines' runtime compatibility.
Do not run an npm or browser installer to update this package: update the Nix pins and rebuild.

The wrapper binds `PLAYWRIGHT_BROWSERS_PATH` to its own browser set, even inside the documentation devshell, and disables update notifications.
On Linux it supplies a default fontconfig with DejaVu fonts, so the headless shell renders text without depending on host fonts.
The sole upstream code patch removes the fallback to a separately installed branded Chrome.
With no explicit channel, Playwright uses its bundled headless shell for headless execution and bundled Chromium for headed execution.
Explicit CLI, environment, and project configuration retain upstream precedence; the wrapper neither parses arguments nor changes directory.

## Consumers

The default devshell includes the executable.
Home Manager's `ai-capabilities` aggregate pairs it with the matching upstream skill through the existing shared skill pipeline.
Both the human `ai` aggregate and dedicated Omnigent workers import that capability group; the lighter human `agents` aggregate is unchanged.
There is no system daemon or activation-time installer.

## Verification

```sh
nix build .#checks.aarch64-darwin.package-playwright-cli-test-smoke
nix build .#checks.x86_64-linux.package-playwright-cli-test-smoke
nix develop -c bash -c 'bash pkgs/by-name/playwright-cli/smoke.sh "$(command -v playwright-cli)"'
```

The smoke test uses an isolated temporary home and session, opens `about:blank`, interacts with a button, verifies text and rendering, snapshots, and closes.
It supplies a deliberately wrong inherited browser path and checks project-relative artifact output.
The build check explicitly disables Chromium's nested sandbox for this trusted fixture because Darwin build accounts cannot initialize it.
The interactive invocation preserves upstream policy: bundled Chromium is unsandboxed by default on Linux, while Darwin defaults to enabling its browser sandbox.
This capability is not a security boundary for untrusted browsing or agent code.
Neither test visits an external site or uses an existing user's browser profile.
