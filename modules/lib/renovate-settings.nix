# Renovate's command allowlist, as static flake data. The renovate aspect
# (modules/nixos/renovate.nix) passes it to services.renovate.settings, and
# the renovate-allowed-commands check compares .github/renovate.json's
# postUpgradeTasks commands against it without evaluating any host
# configuration. Each entry is an anchored regex Renovate tests against a
# compiled task command; they use only anchors, literals and an escaped dot,
# on which JavaScript and Oniguruma (jq's `test`) agree.
{ ... }:
{
  flake.lib.renovateSettings = {
    allowedCommands = [
      "^nix flake lock$"
      "^nix run \\.#regenerate-bun-nix$"
      "^just bun-repin-playwright$"
      "^bun install --ignore-scripts$"
    ];
  };
}
