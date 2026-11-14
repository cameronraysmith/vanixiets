# Upstream release binaries: 3.0 rewrote the CLI in Rust, replacing the Deno
# source build. This trusts upstream's release artifacts rather than building
# from source.
{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  autoPatchelfHook,
  versionCheckHook,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "linear-cli";
  version = "3.1.0";

  src = finalAttrs.passthru.sources.${stdenv.hostPlatform.system};

  dontConfigure = true;
  dontBuild = true;
  # The darwin binary carries an ad-hoc linker signature that stripping would
  # invalidate.
  dontStrip = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # libgcc_s.so.1
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 linear $out/bin/linear
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru = {
    sources = {
      "aarch64-darwin" = fetchurl {
        url = "https://github.com/schpet/linear-cli/releases/download/v${finalAttrs.version}/linear-aarch64-apple-darwin.tar.xz";
        hash = "sha256-u6gc884Z80hvGtpSz5hBqNdJ/KcWM46mhOazsIpwaVQ=";
      };
      "x86_64-darwin" = fetchurl {
        url = "https://github.com/schpet/linear-cli/releases/download/v${finalAttrs.version}/linear-x86_64-apple-darwin.tar.xz";
        hash = "sha256-2ePOpPVwO/wqPJhifku2nXUyrzmp1SMWUCWpAVOS4Lc=";
      };
      "x86_64-linux" = fetchurl {
        url = "https://github.com/schpet/linear-cli/releases/download/v${finalAttrs.version}/linear-x86_64-unknown-linux-gnu.tar.xz";
        hash = "sha256-v3cSCXzmoB6KN53oNX7KZtV0gFAgHTNrp4e2rTaH8+c=";
      };
      "aarch64-linux" = fetchurl {
        url = "https://github.com/schpet/linear-cli/releases/download/v${finalAttrs.version}/linear-aarch64-unknown-linux-gnu.tar.xz";
        hash = "sha256-SwsVtpRk6LamZSkNcCgXZUviEkzx1Y+tfX7VdU+UMdc=";
      };
    };
    # The release archives carry only the executable; the upstream agent skill
    # (flake.lib.linearSkills, apm-skills-compose) comes from the tagged tree.
    # `rev` is the full tag commit because the apm.yml drift guard compares it.
    skillSrc = fetchFromGitHub {
      owner = "schpet";
      repo = "linear-cli";
      rev = "02571d34be662e5487204841fb80bf23ed79b4f0";
      hash = "sha256-Bk4UPFqKVFH51iqiEhCSVfy/CX8CBnD8pHMMCIT83Pw=";
    };
    updateScript = ./update.sh;
  };

  meta = {
    description = "Manage Linear issues from the command line";
    homepage = "https://github.com/schpet/linear-cli";
    changelog = "https://github.com/schpet/linear-cli/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.isc;
    mainProgram = "linear";
    platforms = builtins.attrNames finalAttrs.passthru.sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
