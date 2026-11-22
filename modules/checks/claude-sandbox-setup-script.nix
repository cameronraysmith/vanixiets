# Holds the `claude-sandbox-setup` app (modules/apps/claude-sandbox-setup.nix and
# its .sh sidecar), the Claude Code cloud environment's setup step, and the
# bootstrap its setup box holds. Evaluation-time obligations: the asserts fire
# when this attribute is evaluated, over the package's script text; its build
# depends on the package, whose writeShellApplication build shellchecks it.
#
# - the bootstrap is at most 200 columns per line, a tab counting 8, since the
#   platform refuses a wider setup-script line (A187);
# - the bootstrap that the app module's header comment and the profile's README
#   document equals the lines generated here from lib/caches.nix;
# - the script realises with `--max-jobs 0 --option builders ''`, so the
#   profile's closure is never built;
# - its C, S and K are the two caches' entries in lib/caches.nix, S and K as
#   bash arrays expanded only quoted, since the Q97 probe saw an unquoted
#   string split into arguments;
# - it ends in `exit 0`, since a non-zero setup step stops the session from
#   starting (A170).
{ lib, ... }:
let
  caches = import ../../lib/caches.nix;
  hosts = [
    "cache.scientistexperience.net"
    "cache.nixos.org"
  ];
  pick =
    prefix: entries:
    let
      picked = lib.filter (e: lib.any (h: lib.hasPrefix (prefix h) e) hosts) entries;
    in
    assert lib.assertMsg (
      lib.length picked == lib.length hosts
    ) "lib/caches.nix must name exactly one entry per host in ${toString hosts}";
    picked;
  substituters = pick (h: "https://${h}") caches.substituters;
  publicKeys = pick (h: "${h}-") caches.publicKeys;
  fleetCache = lib.head (lib.filter (lib.hasPrefix "https://${lib.head hosts}") substituters);

  # One `nix run` command split with `\` continuations: the platform refuses a
  # setup-script line wider than 200 columns, a tab counting 8 (A187).
  bootstrap = [
    "#!/bin/bash"
    "nix run \\"
    "  --option substituters ${lib.escapeShellArg (lib.concatStringsSep " " substituters)} \\"
    "  --option trusted-public-keys ${lib.escapeShellArg (lib.concatStringsSep " " publicKeys)} \\"
    "  --option accept-flake-config false \\"
    "  ${lib.escapeShellArg "git+https://github.com/cameronraysmith/vanixiets?ref=main&shallow=1#claude-sandbox-setup"}"
    "exit 0"
  ];
  columns = line: lib.stringLength line + 7 * (lib.length (lib.splitString "\t" line) - 1);
  wide = lib.filter (line: columns line > 200) bootstrap;
  documents = {
    "modules/apps/claude-sandbox-setup.nix" = lib.concatMapStrings (l: "#   ${l}\n") bootstrap;
    "modules/home/users/claude-sandbox/README.md" = lib.concatLines bootstrap;
  };
  undocumented = lib.filter (
    file: !lib.hasInfix documents.${file} (builtins.readFile (../.. + "/${file}"))
  ) (lib.attrNames documents);

  sidecar = "modules/apps/claude-sandbox-setup.sh";
  assignments = [
    "C=${lib.escapeShellArg fleetCache}"
    "S=(${lib.escapeShellArgs substituters})"
    "K=(${lib.escapeShellArgs publicKeys})"
  ];
  quoted = [
    "\"\${S[*]}\""
    "\"\${K[*]}\""
    "\"\${O[@]}\""
  ];
in
{
  perSystem =
    {
      pkgs,
      system,
      config,
      ...
    }:
    let
      package = config.packages.claude-sandbox-setup;
      script = package.text;
      lines = lib.filter (line: line != "") (
        map (line: lib.head (builtins.match "[[:space:]]*(.*)" line)) (lib.splitString "\n" script)
      );
      text = builtins.replaceStrings [ "\n" ] [ " " ] script;
      unquoted = builtins.replaceStrings quoted (map (_: "") quoted) text;
      missing = lib.filter (a: !lib.elem a lines) assignments;
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        claude-sandbox-setup-script =
          assert lib.assertMsg (wide == [ ])
            "the setup box's bootstrap has lines over 200 columns (a tab counts 8), which the platform refuses (A187): ${lib.concatStringsSep " | " wide}";
          assert lib.assertMsg (undocumented == [ ])
            "the setup box's bootstrap, generated from lib/caches.nix, is not documented verbatim in: ${lib.concatStringsSep ", " undocumented}; expected:\n${lib.concatLines bootstrap}";
          assert lib.assertMsg (lib.hasInfix "--max-jobs 0 --option builders ''" text)
            "claude-sandbox-setup must realise with `--max-jobs 0 --option builders ''`, never building the profile's closure";
          assert lib.assertMsg (
            missing == [ ]
          ) "claude-sandbox-setup must set, from lib/caches.nix: ${lib.concatStringsSep " | " missing}";
          assert lib.assertMsg
            (
              lib.all (v: lib.length (lib.filter (lib.hasPrefix "${v}=") lines) == 1) [
                "C"
                "S"
                "K"
                "O"
              ]
              && lib.hasPrefix "O=(" (lib.findFirst (lib.hasPrefix "O=") "" lines)
              && lib.all (q: lib.hasInfix q text) quoted
            )
            "claude-sandbox-setup must set C, S, K and O once each, O as a bash array, and expand them as ${lib.concatStringsSep ", " quoted}";
          assert lib.assertMsg (
            builtins.match ".*\\$\\{?[SKO]([^A-Za-z0-9_].*)?" unquoted == null
          ) "claude-sandbox-setup expands S, K or O other than as ${lib.concatStringsSep ", " quoted}";
          assert lib.assertMsg (
            lib.last lines == "exit 0"
          ) "${sidecar} must end in `exit 0`, not `${lib.last lines}`";
          pkgs.runCommand "claude-sandbox-setup-script" { } ''
            test -x ${lib.getExe package}
            touch "$out"
          '';
      };
    };
}
