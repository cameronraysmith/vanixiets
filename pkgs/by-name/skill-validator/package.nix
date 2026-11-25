# Agent Skills spec validator; checks.x86_64-linux.skills-spec-conformance runs
# its offline `validate structure` over every first-party skill.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  versionCheckHook,
}:
let
  inherit
    ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "skill-validator"; })
    pin
    pinPlan
    ;
  planned = (pinPlan pin.version).artifacts;
  inherit (pin.artifacts.src) sourceBuild;
in
buildGoModule (finalAttrs: {
  pname = "skill-validator";
  inherit (pin) version;

  src = fetchFromGitHub (planned.src.sourceBuild.fetchFromGitHub // { inherit (sourceBuild) hash; });

  vendorHash = sourceBuild.depsHash.go.hash;

  subPackages = [ "cmd/skill-validator" ];

  env.CGO_ENABLED = "0";

  ldflags = [
    "-s"
    "-w"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru = {
    inherit pin pinPlan;
  };

  meta = {
    description = "Validate Agent Skills against the agentskills.io specification";
    homepage = "https://github.com/agent-ecosystem/skill-validator";
    changelog = "https://github.com/agent-ecosystem/skill-validator/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    mainProgram = "skill-validator";
    platforms = lib.platforms.unix;
  };
})
