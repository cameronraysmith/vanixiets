{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go_1_26,
}:

(buildGoModule.override { go = go_1_26; }) {
  pname = "beads-next";
  version = "0-unstable-2026-02-22";

  src = fetchFromGitHub {
    owner = "steveyegge";
    repo = "beads";
    rev = "362608a6a3a7e54ca1ca890d7f9baa3ef5dd256c";
    hash = "sha256-iH4h9Pos/t3db8CILuerQYmqZVCSZmFq9q5mu+rvh7U=";
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

  meta = {
    description = "Beads issue tracker (development build from main)";
    homepage = "https://github.com/steveyegge/beads";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    mainProgram = "bd-next";
    platforms = lib.platforms.unix;
  };
}
