{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go_1_26,
  nix-update-script,
}:

(buildGoModule.override { go = go_1_26; }) {
  pname = "beads-next";
  version = "0.55.4-unstable-2026-02-23";

  src = fetchFromGitHub {
    owner = "steveyegge";
    repo = "beads";
    rev = "9b745dce1515885760ad71e82a2adf2f45f16b9e";
    hash = "sha256-jxB8qSBuUWb8K/n4TotZBdOEvVh6CBonM7iH10GJrxo=";
  };

  vendorHash = "sha256-DlEnIVNLHWetwQxTmUNOAuDbHGZ9mmLdITwDdviphPs=";

  postPatch = ''
    sed -i '/^toolchain /d' go.mod
  '';

  subPackages = [ "cmd/bd" ];

  doCheck = false;

  postInstall = ''
    mv $out/bin/bd $out/bin/bd-next
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch=main" ];
  };

  meta = {
    description = "Beads issue tracker (development build from main)";
    homepage = "https://github.com/steveyegge/beads";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    mainProgram = "bd-next";
    platforms = lib.platforms.unix;
  };
}
