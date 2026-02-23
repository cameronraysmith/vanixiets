{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go_1_26,
  icu,
  nix-update-script,
}:

# rec required when src references version (tag-based pin)
(buildGoModule.override { go = go_1_26; }) rec {
  pname = "beads-next";
  # --- pin mode: uncomment one block, comment the other ---

  # pin to release tag
  version = "0.56.1";
  src = fetchFromGitHub {
    owner = "steveyegge";
    repo = "beads";
    rev = "v${version}";
    hash = "sha256-hp+mKVCSzxxxUtOqspXuTbOJpeC8K9+UmmXSDr5Xa0k=";
  };

  # pin to commit on main
  # version = "0.55.4-unstable-2026-02-23";
  # src = fetchFromGitHub {
  #   owner = "steveyegge";
  #   repo = "beads";
  #   rev = "9b745dce1515885760ad71e82a2adf2f45f16b9e";
  #   hash = "sha256-jxB8qSBuUWb8K/n4TotZBdOEvVh6CBonM7iH10GJrxo=";
  # };

  vendorHash = "sha256-DlEnIVNLHWetwQxTmUNOAuDbHGZ9mmLdITwDdviphPs=";

  buildInputs = [ icu ];

  postPatch = ''
    sed -i '/^toolchain /d' go.mod
  '';

  subPackages = [ "cmd/bd" ];

  doCheck = false;

  postInstall = ''
    mv $out/bin/bd $out/bin/bd-next
  '';

  # update from latest release tag (default nix-update behavior)
  passthru.updateScript = nix-update-script { };

  # update from latest commit on main
  # passthru.updateScript = nix-update-script {
  #   extraArgs = [ "--version=branch=main" ];
  # };

  meta = {
    description = "Beads issue tracker (development build from main)";
    homepage = "https://github.com/steveyegge/beads";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    mainProgram = "bd-next";
    platforms = lib.platforms.unix;
  };
}
