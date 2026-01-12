# gastown - Multi-agent orchestration framework
#
# Coordinates AI agents (particularly Claude Code) working across
# distributed software projects, supporting 20-30+ simultaneous agents.
#
# Source: https://github.com/steveyegge/gastown
#
# Binary name: upstream uses `gt`, which is preserved here.
# graphite-cli (also uses `gt`) is renamed to `grt` via overlay.
# See: modules/nixpkgs/overlays/overrides.nix
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  nix-update-script,
  versionCheckHook,
}:

buildGoModule (finalAttrs: {
  pname = "gastown";
  version = "0.2.6";

  src = fetchFromGitHub {
    owner = "steveyegge";
    repo = "gastown";
    tag = "v${finalAttrs.version}";
    hash = "sha256-HqHBh1fP+TglMrA/5OUBpgowl5PxQJkRFiANei+cXWI=";
  };

  vendorHash = "sha256-ripY9vrYgVW8bngAyMLh0LkU/Xx1UUaLgmAA7/EmWQU=";

  subPackages = [ "cmd/gt" ];

  ldflags = [
    "-s"
    "-w"
    "-X=github.com/steveyegge/gastown/internal/cmd.Version=${finalAttrs.version}"
    "-X=github.com/steveyegge/gastown/internal/cmd.Build=nix"
  ];

  # Tests require git worktrees, tmux, and other runtime dependencies
  doCheck = false;

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/gt";
  versionCheckProgramArg = "version";
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Multi-agent orchestration framework for coordinating AI agents across distributed projects";
    longDescription = ''
      Gastown provides infrastructure for scaling from a few AI agents to 20-30+
      working simultaneously across software projects. Features include:

      - Work persistence through crashes/restarts
      - Structured agent identity and attribution
      - Autonomous execution (propulsion principle)
      - Inter-agent coordination via mail system
      - Workspace hierarchy: Town → Rig → Agents
      - Agent roles: Mayor, Witness, Refinery, Polecat, Crew
      - Convoy tracking for batched work across rigs
      - Molecule workflow templates with phase states
    '';
    homepage = "https://github.com/steveyegge/gastown";
    changelog = "https://github.com/steveyegge/gastown/blob/main/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "gt";
    platforms = lib.platforms.unix;
  };
})
