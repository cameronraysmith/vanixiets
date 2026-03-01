{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go_1_26,
  icu,
  nix-update-script,
}:

let
  version = "0.57.0-unstable-2026-03-01";
  rev = "34c0c8be62fd7c40ab0b37d773fbc8cb7b60c268";
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
    hash = "sha256-oBRw/ytS9mzWDtrGFpg5quefZrCBIpe0Hv2wAdUkFzQ=";
  };

  vendorHash = "sha256-uf6ET13OImaGk22I9MJ/wJvX8F0bXaEkf726De/80PY=";

  buildInputs = [ icu ];

  postPatch = ''
    sed -i '/^toolchain /d' go.mod
  '';

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${version}"
    "-X main.Build=nix"
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
