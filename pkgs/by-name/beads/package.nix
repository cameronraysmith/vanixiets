{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go_1_26,
  icu,
  nix-update-script,
}:

let
  version = "0.57.0-unstable-2026-03-03";
  rev = "9e093c188a4f6a27e18447074a07af95209de917";
in
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
  inherit version;
  src = fetchFromGitHub {
    owner = "cameronraysmith";
    repo = "beads";
    inherit rev;
    hash = "sha256-LeRQu7NMdJNGnDY3alKJ0q4c/dha1KGSeQjBOiCMI0g=";
  };

  vendorHash = "sha256-OL6QGf4xSMpEbmU+41pFdO0Rrs3H162T3pdiW9UfWR0=";

  buildInputs = [ icu ];

  postPatch = ''
    sed -i '/^toolchain /d' go.mod
  '';

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${version}"
    "-X main.Build=${builtins.substring 0 7 rev}"
    "-X main.Commit=${rev}"
  ];

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
