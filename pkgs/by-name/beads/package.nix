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
  version = "1.0.0-unstable-2026-04-04";
  rev = "f58bd1da3637655d4f011dfacbdeeb2cb0974cb5";
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
    hash = "sha256-XBMQ1lO4ZJPWkwqrqnpE3L21rigeCHEfBIc78vpnV3Y=";
  };

  vendorHash = "sha256-7DJgqJX2HDa9gcGD8fLNHLIXvGAEivYeDYx3snCUyCE=";

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
