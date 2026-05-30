{
  lib,
  rustPlatform,
  fetchFromGitHub,
  nix-update-script,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "linear-cli";
  version = "0.3.26";

  src = fetchFromGitHub {
    owner = "Finesssee";
    repo = "linear-cli";
    tag = "v${finalAttrs.version}";
    hash = "sha256-fxDvLHwG7ceSr5OCrCBXoVZtmvG1/keBOzh2ckwe8cA=";
  };

  cargoHash = "sha256-dKOqu1XEAVN9tHE/QxRARJxuUxWjIT9246lJ5T+cr58=";

  preCheck = ''
    export HOME=$(mktemp -d)
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgramArg = "--version";

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Powerful CLI for Linear.app - manage issues, projects, cycles, and more from your terminal";
    homepage = "https://github.com/Finesssee/linear-cli";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ cameronraysmith ];
    mainProgram = "linear-cli";
    platforms = lib.platforms.unix;
  };
})
