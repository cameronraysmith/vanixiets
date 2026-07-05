{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  zlib,
  nix-update-script,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "git-repo-manager";
  version = "0.10.0";

  src = fetchFromGitHub {
    owner = "hakoerber";
    repo = "git-repo-manager";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Lp1lN+rEjSivfiYOe0MWTvPyDpn1nmYE17yAo2XhzcQ=";
  };

  cargoHash = "sha256-gaoyku/BloIynmBI3rzLB/Hn9D/2LTryeJOmB1NqPnI=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    openssl
    zlib
  ];

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Declarative manager for multiple git repositories and worktrees";
    homepage = "https://github.com/hakoerber/git-repo-manager";
    changelog = "https://github.com/hakoerber/git-repo-manager/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.gpl3Only;
    mainProgram = "grm";
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
})
