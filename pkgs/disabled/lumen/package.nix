# lumen - AI-powered CLI for git workflows
#
# Uses AI to generate commit messages, summarize git diffs,
# explain complex changes, and more. Supports jujutsu (jj) via
# the optional jj feature (enabled by default).
#
# Source: https://github.com/jnsahaj/lumen
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  versionCheckHook,
  nix-update-script,
}:
rustPlatform.buildRustPackage rec {
  pname = "lumen";
  version = "2.11.0";

  src = fetchFromGitHub {
    owner = "jnsahaj";
    repo = "lumen";
    rev = "v${version}";
    hash = "sha256-VMFsM2gykzRzrn11r1Y2/xrHXMOL4rKc5UiFi/mPpoQ=";
  };

  cargoHash = "sha256-ngkNKDYW55Vc2vMXmDSvKHChc1WnwoS8EbHPdrOSPKs=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  # jj feature enabled by default in upstream Cargo.toml

  doCheck = false;

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/lumen";
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    homepage = "https://github.com/jnsahaj/lumen";
    description = "AI-powered command-line tool for git workflows";
    longDescription = ''
      lumen uses AI to streamline git workflow - from generating commit
      messages to explaining complex changes. Features include:
      - Generate commit messages from staged changes
      - Summarize git diffs or past commits
      - Explain what changed and why
      - Support for both git and jujutsu (jj)
    '';
    changelog = "https://github.com/jnsahaj/lumen/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "lumen";
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
}
