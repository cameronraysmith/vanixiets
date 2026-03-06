{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go_1_26,
  icu,
  nix-update-script,
}:

let
  version = "0.59.0-unstable-2026-03-06";
  rev = "2df714ffcf02d378d56ad06314bc13c7c3f4a16a";
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
    owner = "steveyegge";
    repo = "beads";
    inherit rev;
    hash = "sha256-wtMzh1BqGt7lLNVV3xEGo5PgEk2rksgOEkYOHMN3+as=";
  };

  vendorHash = "sha256-ygZPi56fVEHaEShGVGpObFkrLs1DHrM8i2Y4BktMmpA=";

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
