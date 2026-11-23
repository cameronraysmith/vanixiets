# Agent Skills spec validator; checks.x86_64-linux.skills-spec-conformance runs
# its offline `validate structure` over every first-party skill.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  versionCheckHook,
}:

buildGoModule (finalAttrs: {
  pname = "skill-validator";
  version = "1.8.0";

  src = fetchFromGitHub {
    owner = "agent-ecosystem";
    repo = "skill-validator";
    tag = "v${finalAttrs.version}";
    hash = "sha256-pWtOfJCBDihUO87jSzupLLxxrrEKgHycBdEK/DRbax8=";
  };

  vendorHash = "sha256-q8JRenRhDEzYO9Ub3SnDQ7phG0bWRJzDU2vPDllIrwU=";

  subPackages = [ "cmd/skill-validator" ];

  env.CGO_ENABLED = "0";

  ldflags = [
    "-s"
    "-w"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

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
