{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go_1_26,
  icu,
  nix-update-script,
}:

(buildGoModule.override { go = go_1_26; }) {
  pname = "beads";
  # --- pin mode: uncomment one block, comment the other ---

  # pin to release tag
  # version = "0.56.1";
  # src = fetchFromGitHub {
  #   owner = "steveyegge";
  #   repo = "beads";
  #   rev = "v${version}";
  #   hash = "sha256-hp+mKVCSzxxxUtOqspXuTbOJpeC8K9+UmmXSDr5Xa0k=";
  # };

  # pin to commit on main
  version = "0.56.1-unstable-2026-02-25";
  src = fetchFromGitHub {
    owner = "steveyegge";
    repo = "beads";
    rev = "a22da6f46fda440ae13fa6564a1716ce662cd4c1";
    hash = "sha256-IQEJh7xWX0J686yCr8Qz5JHqTENfcyTZRQ01TB7r49A=";
  };

  vendorHash = "sha256-nhhntZqWUEDExvXyhlC/640uCU0yUN7J7+P02CuI8YI=";

  buildInputs = [ icu ];

  postPatch = ''
    sed -i '/^toolchain /d' go.mod
  '';

  subPackages = [ "cmd/bd" ];

  doCheck = false;

  # update from latest release tag (default nix-update behavior)
  # passthru.updateScript = nix-update-script { };

  # update from latest commit on main
  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch=main" ];
  };

  meta = {
    description = "Beads issue tracker";
    homepage = "https://github.com/steveyegge/beads";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    mainProgram = "bd";
    platforms = lib.platforms.unix;
  };
}
