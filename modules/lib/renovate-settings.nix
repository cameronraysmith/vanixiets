# Renovate's command allowlist and the Phase 1 global packageRules, as
# static flake data. The renovate aspect (modules/nixos/renovate.nix) passes
# both to services.renovate.settings, and the renovate-allowed-commands check
# compares every postUpgradeTasks command, here and in .github/renovate.json,
# against the allowlist without evaluating any host configuration. Each
# allowlist entry is an anchored regex Renovate tests against a compiled task
# command; they use only anchors, literals and an escaped dot, on which
# JavaScript and Oniguruma (jq's `test`) agree.
{ ... }:
{
  flake.lib.renovateSettings = {
    allowedCommands = [
      "^nix flake lock$"
      "^nix run \\.#regenerate-bun-nix$"
      "^just bun-repin-playwright$"
      "^bun install --ignore-scripts$"
    ];

    # Phase 1 only; removed by tasks.md 7.4, when these rules move into
    # .github/renovate.json. Global rules are concatenated before the
    # repository's, so the hosted app, which reads only the repository file,
    # sees no change while they live here. postUpgradeTasks is not mergeable:
    # the Playwright rule must stay after the generic custom.regex rule, and
    # every task rule spells out all three fields.
    phase1PackageRules = [
      {
        description = "Regex-manager flake.nix ref bumps never touch flake.lock; re-lock in the same commit so nixbot evaluates a complete tree.";
        matchManagers = [ "custom.regex" ];
        postUpgradeTasks = {
          commands = [ "nix flake lock" ];
          fileFilters = [ "flake.lock" ];
          executionMode = "branch";
        };
      }
      {
        description = "bun manager updates bun.lock; regenerate bun.nix from it in the same commit.";
        matchManagers = [ "bun" ];
        postUpgradeTasks = {
          commands = [ "nix run .#regenerate-bun-nix" ];
          fileFilters = [ "bun.nix" ];
          executionMode = "branch";
        };
      }
      {
        description = "npm playwright is derived, not tracked: its version must equal the playwright-web-flake driver (pkgs/by-name/vanixiets-docs/package.nix guards the browsers.json revision match). Renovate never proposes it on its own.";
        matchManagers = [ "bun" ];
        matchPackageNames = [
          "playwright"
          "@playwright/test"
        ];
        enabled = false;
      }
      {
        description = "A playwright-web-flake ref bump re-locks the flake, re-pins npm playwright to the new driver version, reconciles bun.lock and regenerates bun.nix in one commit. Both coordinates are listed so a fork-drop keeps the rule. Must stay after the custom.regex rule: postUpgradeTasks is not mergeable, so this object replaces that one.";
        matchManagers = [ "custom.regex" ];
        matchPackageNames = [
          "cameronraysmith/playwright-web-flake"
          "pietdevries94/playwright-web-flake"
        ];
        groupName = "playwright";
        postUpgradeTasks = {
          commands = [
            "nix flake lock"
            "just bun-repin-playwright"
            "bun install --ignore-scripts"
            "nix run .#regenerate-bun-nix"
          ];
          fileFilters = [
            "flake.lock"
            "packages/docs/package.json"
            "bun.lock"
            "bun.nix"
          ];
          executionMode = "branch";
        };
      }
    ];
  };
}
