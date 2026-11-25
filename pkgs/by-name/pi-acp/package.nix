# pi-acp is the Agent Client Protocol adapter omnigent runs in front of atomic
# (modules/home/ai/omnigent/acp.nix). It was previously started as
# `bunx pi-acp@<version>`, which fetched it from npm at every cold session
# start; building it here makes session start independent of the registry and
# routes upgrades through review like atomic's.
#
# Built from the tagged GitHub source with upstream's package-lock.json (the
# npm tarball ships only a tsup bundle and no lockfile); `npm run build` is
# upstream's tsup bundle, and the check phase runs upstream's typecheck and
# tests against the patched source.
#
# atomic-sqlite-sessions.patch: atomic >= 0.9.38 stores sessions in SQLite.
# get_state reports no sessionFile and `--session` takes a session id, so
# unpatched pi-acp never records atomic sessions, lists only pi's JSONL files,
# and refuses /export. The patch records the session id where pi-acp records a
# JSONL path, so session/load restarts atomic with `--session <id>`,
# session/list includes the sessions this adapter recorded, and /export relies
# on atomic's messageCount instead of reading a session file. Sessions created
# outside pi-acp (atomic's own TUI) remain unlisted, listed atomic sessions
# carry no title, and session/delete forgets the record but leaves atomic's
# database row. Omnigent uses none of list/load/export/delete; the patch only
# keeps them usable for an interactive ACP client. Drop the patch when
# upstream handles atomic's session store.
#
# pin.json pins the version, the source hash and npmDepsHash; Renovate proposes
# GitHub releases and `nix run .#realize-pin -- pi-acp <version>` realizes one.
# The patch is applied as is to every version: when a release moves the code it
# touches, the realizer fails computing npmDepsHash (npmDeps applies the
# patches), and the patch must be rebased by hand.
# source: https://github.com/svkozak/pi-acp
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  runCommand,
  writableTmpDirAsHomeHook,
}:
let
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "pi-acp"; })
    pin
    pinPlan
    ;
  planned = (pinPlan pin.version).artifacts;
  inherit (pin.artifacts.src) sourceBuild;

  # One ACP initialize round trip against the given binary; it does not start
  # atomic. pi-acp exits as soon as stdin ends, possibly before replying, so
  # stdin stays open until the reply has been read.
  initializeProbe = bin: ''
    { printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}'; sleep 10; } \
      | timeout 30 ${bin} | head -n 1 > response.json
    grep -q '"protocolVersion":1' response.json
    grep -q '"loadSession":true' response.json
  '';
in
buildNpmPackage (finalAttrs: {
  pname = "pi-acp";
  inherit (pin) version;

  src = fetchFromGitHub (planned.src.sourceBuild.fetchFromGitHub // { inherit (sourceBuild) hash; });

  patches = [ ./atomic-sqlite-sessions.patch ];

  nodejs = nodejs_22;
  npmDepsHash = sourceBuild.depsHash.npm.hash;

  doCheck = true;
  nativeCheckInputs = [ writableTmpDirAsHomeHook ];
  # Upstream's `npm test`, minus the two session-path tests: their fake pi
  # launcher is a `#!/usr/bin/env node` script, and the build sandbox has no
  # /usr/bin/env.
  checkPhase = ''
    runHook preCheck
    npm run typecheck
    node --import tsx --test --test-skip-pattern='session paths? intact' 'test/**/*.test.ts'
    runHook postCheck
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${initializeProbe ''"$out/bin/pi-acp"''}
    grep -q '"version":"${finalAttrs.version}"' response.json
    rm response.json
    runHook postInstallCheck
  '';

  strictDeps = true;

  passthru = {
    inherit pin pinPlan;

    # installCheck runs while $out is still being built; this probes the
    # finished, read-only store path.
    tests.initialize = runCommand "pi-acp-test-initialize" { meta.timeout = 60; } ''
      ${initializeProbe (lib.getExe finalAttrs.finalPackage)}
      touch "$out"
    '';
  };

  meta = {
    description = "Agent Client Protocol adapter for the pi coding agent, used here in front of atomic";
    homepage = "https://github.com/svkozak/pi-acp";
    changelog = "https://github.com/svkozak/pi-acp/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "pi-acp";
    platforms = lib.platforms.unix;
  };
})
