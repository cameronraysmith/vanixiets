# configd rereads /etc/resolver only when the directory changes.
#
# macOS consults /etc/resolver/<domain> for names under that domain
# (modules/system/mesh-dns.nix, modules/system/zt-dns.nix). configd's
# IPMonitor plugin watches /etc/resolver with an FSEventStream and recomputes
# the DNS configuration from the files there when the stream reports an event
# (configd-1405.100.8 Plugins/IPMonitor/dns-configuration.c:1836-1866,
# callback :1780-1802). nix-darwin delivers each file as a symlink
# /etc/resolver/<domain> -> /etc/static/resolver/<domain> and activates a new
# generation by repointing /etc/static (modules/system/etc.nix,
# system.activationScripts.etc at the pinned nix-darwin); the links under
# /etc/resolver already point at /etc/static and are left alone, so no event
# is raised and configd keeps the previous generation's flags and name
# servers. After #4002 `scutil --dns` showed both zones A-only until
# `sudo touch -h` on the two links (logs/cam109-evidence/9.10-stibnite-*.log,
# 9.10-stibnite-after-touch-*.log).
#
# Every activation therefore runs `touch -h` on each enabled environment.etc
# entry whose target is under resolver/, which changes the link's own times
# and raises the event. It runs unconditionally: comparing the old and new
# file contents would skip the touch whenever a previous activation changed
# the contents but stopped before a touch (an interrupted activation, or any
# generation activated before this module existed), and a reread costs configd
# one DNS configuration rebuild. The lines lead postActivation (lib.mkBefore),
# which nix-darwin's activation-scripts.nix splices after
# system.activationScripts.etc, so the links exist and point at the new
# /etc/static, and no later postActivation snippet failing under set -e can
# skip them. coreutils' touch -h (activationPath) never creates a missing file.
#
# flake.lib.resolverReloadObligations.failures, asserted by
# modules/checks/machines.nix on every darwin machine check, fails unless the
# rendered activation script carries one such line per managed file after the
# /etc link loop; checks.x86_64-linux.darwin-resolver-reload exercises its
# judge on fixtures.
{ config, lib, ... }:
let
  # The targets of the enabled environment.etc entries under resolver/.
  resolverTargets =
    etc:
    lib.filter (lib.hasPrefix "resolver/") (
      map (file: file.target) (lib.filter (file: file.enable) (lib.attrValues etc))
    );

  touchLine = target: "touch -h ${lib.escapeShellArg "/etc/${target}"}";

  # The last line of nix-darwin's loop that links /etc/<path> to
  # /etc/static/<path> (modules/system/etc.nix at the pinned nix-darwin).
  linkLoopEnd = "done < <(find -H /etc/static -type l -print0)";

  # The problems with `script`, an activation script's text, for the resolver
  # files `targets`: each needs its touch line after the last line of the
  # /etc link loop. Lines are compared with surrounding blanks trimmed.
  missingReloads =
    { targets, script }:
    let
      trim =
        s:
        let
          m = builtins.match "[[:space:]]*(.*[^[:space:]])[[:space:]]*" s;
        in
        if m == null then "" else lib.head m;
      lines = map trim (lib.splitString "\n" script);
      anchors = lib.filter (i: lib.elemAt lines i == linkLoopEnd) (lib.range 0 (lib.length lines - 1));
      after = lib.drop (lib.last anchors + 1) lines;
    in
    if anchors == [ ] then
      [ "no /etc link loop (`${linkLoopEnd}`)" ]
    else
      map (target: "no `${touchLine target}` after the /etc link loop") (
        lib.filter (target: !lib.elem (touchLine target) after) targets
      );
in
{
  flake.lib.resolverReloadObligations = {
    inherit resolverTargets touchLine missingReloads;
    failures =
      name: hostConfig:
      map (problem: "${name}'s system.activationScripts.script.text: ${problem}") (missingReloads {
        targets = resolverTargets hostConfig.environment.etc;
        script = builtins.unsafeDiscardStringContext hostConfig.system.activationScripts.script.text;
      });
  };

  # Darwin only: NixOS has no /etc/resolver.
  fleetObligations.resolverReloadObligations = {
    classes = [ "darwin" ];
    inherit (config.flake.lib.resolverReloadObligations) failures;
  };

  flake.modules.darwin.base =
    { config, ... }:
    let
      targets = resolverTargets config.environment.etc;
    in
    {
      system.activationScripts.postActivation.text = lib.mkBefore (
        lib.optionalString (targets != [ ]) ''
          # Make configd reread /etc/resolver (modules/darwin/resolver-reload.nix).
          ${lib.concatMapStringsSep "\n" touchLine targets}
        ''
      );
    };
}
