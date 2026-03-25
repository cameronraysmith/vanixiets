{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go_1_26,
  icu,
  nix-update-script,
}:

let
  version = "0.62.0-unstable-2026-03-25";
  rev = "6215721fc7be3bf31592e2f9d1486d4a53429c22";
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
    hash = "sha256-iOjDMEI7lIrvg8PEltxRWCxHB1ZThh975w+Uo7brMDw=";
  };

  vendorHash = "sha256-yrIlyP2fOesS74NqwaDrBK37KCjh3N1DePiF8w9ubOk=";

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
