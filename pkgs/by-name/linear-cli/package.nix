{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  makeWrapper,
  deno,
  jq,
  xz,
  versionCheckHook,
}:

let
  version = "2.0.0";

  # Prebuilt deno-compile binaries published per tag by cargo-dist. Only the
  # Darwin artifacts are usable (see the Linux note below).
  binaries = {
    aarch64-darwin = {
      url = "https://github.com/schpet/linear-cli/releases/download/v${version}/linear-aarch64-apple-darwin.tar.xz";
      hash = "sha256-Eh/h7ubZCyLnbk6Yy7YkR07s2XCkpMYi/U1QiJtX2sw=";
    };
    x86_64-darwin = {
      url = "https://github.com/schpet/linear-cli/releases/download/v${version}/linear-x86_64-apple-darwin.tar.xz";
      hash = "sha256-cp5nFmxQlMiVFQtnLNOkRh+omYl+HyTbzQfBO7O0jBM=";
    };
  };

  # `src` is the upstream SOURCE tree (NOT the binary). Consumers inject the
  # bundled agent skill via `${pkgs.linear-cli.src}/skills` (see
  # modules/home/users/crs58/default.nix aiSkills.extraSkillDirs), so `src` must
  # remain the upstream source tree on every platform.
  src = fetchFromGitHub {
    owner = "schpet";
    repo = "linear-cli";
    rev = "v${version}";
    hash = "sha256-FR6WuTKws75i0T00ASxr6wTHYH8MNOdboJcDYD0aYVM=";
  };

  # Darwin: the upstream prebuilt deno-compile single-file executable.
  binDist = fetchurl {
    inherit
      (binaries.${stdenv.hostPlatform.system}
        or (throw "linear-cli: unsupported darwin system ${stdenv.hostPlatform.system}")
      )
      url
      hash
      ;
  };

  # Linux: a fixed-output derivation (network permitted) that materialises the
  # gitignored `src/__codegen__/` and vendors all dependencies in a REPRODUCIBLE
  # form. The raw DENO_DIR cache is not reproducible (per-fetch jsr/npm metadata,
  # SQLite analysis/v8 caches, random scripts-warned nonces, path-keyed gen/),
  # so we vendor the jsr/https deps as plain source files via
  # `deno cache --vendor` (deterministic) and keep only the content-addressed
  # npm packages from DENO_DIR, dropping the non-deterministic metadata and
  # regenerable caches. The main derivation builds offline against these with
  # `vendor = true` and `--cached-only`.
  denoDeps = stdenv.mkDerivation {
    pname = "linear-cli-deno-deps";
    inherit version src;

    nativeBuildInputs = [ deno ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild

      export HOME="$TMPDIR/home"
      export DENO_DIR="$TMPDIR/deno_dir"
      export DENO_NO_UPDATE_CHECK=1
      mkdir -p "$HOME" "$DENO_DIR"

      # Generate src/__codegen__/{gql.ts,graphql.ts,index.ts} from the committed
      # graphql/schema.graphql via @graphql-codegen/cli.
      deno task codegen

      # Vendor jsr/https deps as plain source files (deterministic); also
      # populates the npm cache under $DENO_DIR/npm.
      deno cache --vendor src/main.ts

      # Reduce DENO_DIR to its reproducible, runtime-necessary subset (the
      # content-addressed npm packages). Drop the non-deterministic or
      # regenerable artifacts: remote/ (now vendored), analysis & v8 caches, the
      # path-keyed gen/ tree, scripts-warned nonces, and npm registry metadata.
      ( cd "$DENO_DIR"
        rm -rf remote gen
        find . -name '*_analysis_cache_v2*' -delete
        find . -name 'v8_code_cache_v2*' -delete
        find . -name '.scripts-warned-*' -delete
        find . -name 'registry.json' -delete
      )

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -r "$DENO_DIR" "$out/deno_dir"
      cp -r vendor "$out/vendor"
      cp -r src/__codegen__ "$out/codegen"

      runHook postInstall
    '';

    dontFixup = true;

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-r5480RsOe3Su7opj5V76nBgm3cVmlzckNAUXRayHLMg=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "linear-cli";
  inherit version src;

  # Two install strategies, selected by host platform:
  #
  #   Darwin: install the upstream prebuilt deno-compile single-file executable
  #   directly. It is a Deno SEA that locates its embedded payload relative to
  #   its own file image, so patchelf/strip must never touch it; on Darwin the
  #   Mach-O loads cleanly without modification.
  #
  #   Linux: the prebuilt SEA cannot be made to work in Nix. Rewriting its ELF
  #   interpreter (autoPatchelfHook --set-interpreter) corrupts the embedded
  #   payload, and launching it through the Nix dynamic loader breaks
  #   /proc/self/exe so Deno can no longer find its payload ("Could not find
  #   standalone binary section"). Instead we run from source with a `deno run`
  #   wrapper over the nixpkgs `deno` (which has the correct Nix interpreter),
  #   following the nixpkgs `era` package pattern. The dependencies are pure
  #   JS/TS (cliffy, graphql, valibot, remark, @std/*) with no native addons,
  #   so no patching is required.

  nativeBuildInputs = [
    versionCheckHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ xz ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    makeWrapper
    jq
  ];

  dontUnpack = stdenv.hostPlatform.isDarwin;
  dontConfigure = true;
  dontBuild = true;

  # On Darwin the prebuilt SEA must not be modified by ELF/strip fixups.
  dontStrip = stdenv.hostPlatform.isDarwin;
  dontPatchELF = stdenv.hostPlatform.isDarwin;

  installPhase =
    lib.optionalString stdenv.hostPlatform.isDarwin ''
      runHook preInstall
      tar xf "${binDist}"
      install -Dm755 linear-*/linear "$out/bin/linear"
      runHook postInstall
    ''
    + lib.optionalString stdenv.hostPlatform.isLinux ''
      runHook preInstall

      mkdir -p "$out/lib"
      cp -r ./. "$out/lib"

      # Drop in the codegen output and vendored jsr/https sources that upstream
      # gitignores / does not ship.
      mkdir -p "$out/lib/src/__codegen__"
      cp -r ${denoDeps}/codegen/. "$out/lib/src/__codegen__/"
      cp -r ${denoDeps}/vendor "$out/lib/vendor"

      # Resolve vendored jsr/https sources offline, and force global npm
      # resolution (nodeModulesDir = none) so deno never tries to create a local
      # node_modules symlink farm inside the read-only store at runtime.
      jq '.vendor = true | .nodeModulesDir = "none"' "$out/lib/deno.json" > "$out/lib/deno.json.tmp"
      mv "$out/lib/deno.json.tmp" "$out/lib/deno.json"

      # `--quiet` mutes deno's "Ignored build scripts" lifecycle-script
      # diagnostic for dev-only deps (e.g. npm:lefthook) that are absent from
      # the `linear` runtime path; we deliberately run without a node_modules
      # dir, so the diagnostic is noise on every invocation.
      makeWrapper ${lib.getExe deno} "$out/bin/linear" \
        --set DENO_DIR "${denoDeps}/deno_dir" \
        --set DENO_NO_UPDATE_CHECK "1" \
        --add-flags "run --quiet --cached-only --no-check -A $out/lib/src/main.ts"

      runHook postInstall
    '';

  doInstallCheck = true;
  versionCheckProgramArg = "--version";

  passthru = {
    updateScript = ./update.sh;
    inherit denoDeps;
  };

  meta = {
    description = "Manage Linear issues from the command line";
    homepage = "https://github.com/schpet/linear-cli";
    license = lib.licenses.mit;
    mainProgram = "linear";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance =
      lib.optionals stdenv.hostPlatform.isDarwin [ lib.sourceTypes.binaryNativeCode ]
      ++ lib.optionals stdenv.hostPlatform.isLinux [ lib.sourceTypes.fromSource ];
  };
})
