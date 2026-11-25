# Renovate's command allowlist, as static flake data. The renovate aspect
# (modules/nixos/renovate.nix) passes it to services.renovate.settings, and
# the renovate-allowed-commands check compares every postUpgradeTasks command
# in .github/renovate.json against it without evaluating any host
# configuration. Each allowlist entry is an anchored regex Renovate tests
# against a compiled task command; they use only anchors, literals, an escaped
# dot, bracket classes and `*`, on which JavaScript and Oniguruma (jq's
# `test`) agree. The realize-pin entry admits one package name and one version
# and no shell metacharacter (openspec automate-package-version-bumps, D8).
{ ... }:
{
  flake.lib.renovateSettings = {
    allowedCommands = [
      "^nix flake lock$"
      "^nix run \\.#regenerate-bun-nix$"
      "^just bun-repin-playwright$"
      "^bun install --ignore-scripts$"
      "^nix run \\.#realize-pin -- [a-z0-9][a-z0-9-]* [0-9A-Za-z][0-9A-Za-z.+_-]*$"
    ];
  };
}
