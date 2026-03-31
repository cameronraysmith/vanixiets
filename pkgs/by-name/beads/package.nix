{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go_1_26,
  icu,
  makeWrapper,
  nix-update-script,
}:

let
  version = "0.63.3-unstable-2026-03-30";
  rev = "3fc9443f3cc05b7eac0eba5ab1983f63aec42382";
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
    hash = "sha256-ext3lwNSTIV4+nlqUq1pGwhCgj81Ep45/rlfBjR3g8s=";
  };

  vendorHash = "sha256-wDTa6E9kW6oV/Vz/CpWH3ZZnOwaw9/qdFHRdZwUY4P8=";

  nativeBuildInputs = [ makeWrapper ];
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

  postInstall = ''
    wrapProgram $out/bin/bd \
      --set BEADS_DOLT_SERVER_MODE 1
  '';

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
