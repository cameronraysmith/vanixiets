{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go_1_26,
  nix-update-script,
}:

(buildGoModule.override { go = go_1_26; }) {
  pname = "beads-next";
  version = "0.55.4-unstable-2026-02-22";

  src = fetchFromGitHub {
    owner = "steveyegge";
    repo = "beads";
    rev = "4766a4f3d9e5c0da1d853e93b22bd0a0700e117e";
    hash = "sha256-JyoVINRmsUbAuSQ2YkRRPwPJ814kZPaE5Drh/a90ZkU=";
  };

  vendorHash = "sha256-yhytpwXJHZo68+dEHUvhgsvFJm+gIhM3eKRXySvz2EU=";

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
