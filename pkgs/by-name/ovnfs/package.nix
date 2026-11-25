{
  lib,
  stdenv,
  buildGo127Module,
  fetchFromGitHub,
  makeBinaryWrapper,
  fuse3,
  go_1_27,
}:
let
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "ovnfs"; })
    pin
    pinPlan
    ;
  planned = (pinPlan pin.version).artifacts;
  inherit (pin.artifacts.src) sourceBuild;
in
# go.mod declares `go 1.27.3`, which the default buildGoModule's toolchain
# (go 1.26) refuses under the GOTOOLCHAIN=local that nixpkgs builds with.
buildGo127Module (finalAttrs: {
  pname = "ovnfs";
  inherit (pin) version;

  src = fetchFromGitHub (planned.src.sourceBuild.fetchFromGitHub // { inherit (sourceBuild) hash; });

  vendorHash = sourceBuild.depsHash.go.hash;

  # Matches upstream's release builds (.goreleaser.yaml). On Darwin this also
  # leaves out the cgo-only FSEvents watcher (watch/watch_darwin.go) and the
  # phys_footprint memory probe (footprint_darwin.go, which then reports 0), so
  # the daemon behaves as the published macOS binary does.
  env.CGO_ENABLED = "0";

  ldflags = [
    "-s"
    "-w"
  ];

  subPackages = [ "." ];

  # The suite mounts FUSE and NFS filesystems for real (.github/workflows/ci.yml),
  # and Darwin builds here run unsandboxed, so it would mount on the build host.
  doCheck = false;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ makeBinaryWrapper ];

  # Linux mounts go through fusermount3 found on PATH (fuse/mount_linux.go).
  # --suffix keeps NixOS's setuid /run/wrappers/bin/fusermount3 ahead of the
  # store copy, which cannot mount as non-root; nixpkgs rclone and plakar wrap
  # the same way.
  postInstall = lib.optionalString stdenv.hostPlatform.isLinux ''
    wrapProgram $out/bin/ovnfs \
      --suffix PATH : ${lib.makeBinPath [ fuse3 ]}
  '';

  # `ovnfs version` reports the module version Go stamps from VCS metadata,
  # which a build from a source tarball lacks, so it prints "(devel)" and
  # versionCheckHook cannot match the release number. The toolchain it reports
  # still proves the binary runs and was built with the toolchain go.mod asks for.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/ovnfs" version | grep -Fx "ovnfs (devel) go${go_1_27.version} ${stdenv.hostPlatform.go.GOOS}/${stdenv.hostPlatform.go.GOARCH}"
    runHook postInstallCheck
  '';

  passthru = {
    inherit pin pinPlan;
  };

  meta = {
    description = "Copy-on-write checkouts of any folder, served to agents over NFS, FUSE or SMB";
    homepage = "https://github.com/stencil-hq/ovnfs";
    changelog = "https://github.com/stencil-hq/ovnfs/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    mainProgram = "ovnfs";
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
})
