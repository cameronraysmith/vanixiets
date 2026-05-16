{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go_1_26,
  icu,
  pkg-config,
  makeWrapper,
  dolt,
  nix-update-script,
  versionCheckHook,
}:

(buildGoModule.override { go = go_1_26; }) (finalAttrs: {
  pname = "beads";
  version = "1.0.4";

  src = fetchFromGitHub {
    owner = "steveyegge";
    repo = "beads";
    tag = "v${finalAttrs.version}";
    hash = "sha256-a356lk3dWJg2VzXmvBL0xVYUMgICDY/6s6A5km8cjBU=";
  };

  vendorHash = "sha256-gTOYABrdQ9T5uxW5QEE8hRWH6AnCPFE/hbB2t1OJTrY=";

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];

  buildInputs = [ icu ];

  # go-icu-regex's cgo directives use raw -licui18n etc. with no
  # `#cgo pkg-config:` line, so pkg-config never runs. On darwin the
  # icu include dir does not otherwise make it into the compiler
  # invocation; pass it explicitly so the build is independent of
  # which cc cgo ends up resolving.
  env = {
    CGO_ENABLED = "1";
    CGO_CFLAGS = "-I${lib.getDev icu}/include";
    CGO_CXXFLAGS = "-I${lib.getDev icu}/include";
    CGO_LDFLAGS = "-L${lib.getLib icu}/lib";
  };

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${finalAttrs.version}"
    "-X main.Build=dev"
  ];

  subPackages = [ "cmd/bd" ];

  doCheck = false;

  # Wrap with dolt on PATH. The BEADS_DOLT_SERVER_MODE env is
  # intentionally NOT set here; it is applied at the module layer.
  postInstall = ''
    wrapProgram $out/bin/bd \
      --prefix PATH : ${lib.makeBinPath [ dolt ]}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "A distributed issue tracker designed for AI-supervised coding workflows";
    homepage = "https://github.com/steveyegge/beads";
    changelog = "https://github.com/steveyegge/beads/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    mainProgram = "bd";
    platforms = lib.platforms.unix;
  };
})
