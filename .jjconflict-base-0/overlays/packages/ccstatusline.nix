{
  lib,
  buildNpmPackage,
  fetchzip,
  jq,
  nix-update-script,
}:
buildNpmPackage (finalAttrs: {
  pname = "ccstatusline";
  version = "2.0.21";

  src = fetchzip {
    url = "https://registry.npmjs.org/ccstatusline/-/ccstatusline-${finalAttrs.version}.tgz";
    hash = "sha256-sy9ZLN7Q8m8Gx2VkmtnSSg1CkAL8o6fRjnHuOLr+Y0Q=";
  };

  npmDepsHash = "sha256-Ux1lp4++OOngrWcGcR0D1PDDADQ+pFILuqD2EiFin9w="; # No runtime deps
  forceEmptyCache = true; # Pre-built tarball with no runtime dependencies

  postPatch = ''
    # Remove devDependencies from package.json since dist/ is pre-built
    ${lib.getExe jq} 'del(.devDependencies, .patchedDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json

    # Generate minimal package-lock.json since npm tarball doesn't include it
    # ccstatusline has no runtime dependencies (only devDependencies which we removed)
    cat > package-lock.json <<EOF
    {
      "name": "ccstatusline",
      "version": "2.0.21",
      "lockfileVersion": 3,
      "requires": true,
      "packages": {
        "": {
          "name": "ccstatusline",
          "version": "2.0.21",
          "license": "MIT",
          "bin": {
            "ccstatusline": "dist/ccstatusline.js"
          },
          "engines": {
            "node": ">=14.0.0"
          }
        }
      }
    }
    EOF
  '';

  dontNpmBuild = true; # Built files already in tarball

  installPhase = ''
        runHook preInstall

        # Create output directories
        mkdir -p $out/bin $out/lib/node_modules/ccstatusline

        # Copy package files
        cp -r dist package.json $out/lib/node_modules/ccstatusline/

        # Create executable wrapper that directly executes the built JS
        cat > $out/bin/ccstatusline <<EOF
    #!/usr/bin/env node
    import('file://$out/lib/node_modules/ccstatusline/dist/ccstatusline.js');
    EOF
        chmod +x $out/bin/ccstatusline

        runHook postInstall
  '';

  # Version check disabled because ccstatusline requires piped JSON input
  # or launches TUI when run without arguments
  doInstallCheck = false;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Highly customizable status line formatter for Claude Code CLI";
    homepage = "https://github.com/sirmalloc/ccstatusline";
    license = lib.licenses.mit;
    maintainers = [ ];
    mainProgram = "ccstatusline";
  };
})
