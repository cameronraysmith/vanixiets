# Type-checks packages/evidence-worker and runs its vitest suite inside real
# workerd through @cloudflare/vitest-plugin, against wrangler.jsonc's own
# bindings with the R2 bucket simulated by Miniflare and seeded by the tests.
# Offline: node_modules comes from the workspace deps output, and miniflare's
# fetch of workers.cloudflare.com/cf.json is disabled.
{ ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      deps = config.packages.vanixiets-docs-deps;
      inherit (pkgs.stdenv.hostPlatform) isLinux;
    in
    {
      checks.evidence-worker = pkgs.stdenv.mkDerivation {
        name = "evidence-worker";
        src = lib.fileset.toSource {
          root = ../..;
          fileset = lib.fileset.unions [
            ../../package.json
            ../../packages/evidence-worker
          ];
        };

        nativeBuildInputs = [ pkgs.nodejs-slim ] ++ lib.optionals isLinux [ pkgs.autoPatchelfHook ];
        buildInputs = lib.optionals isLinux [ pkgs.stdenv.cc.cc.lib ];
        # The bundled workerd is patched by hand below; $out holds no ELFs.
        dontAutoPatchelf = true;
        # Miniflare serves workerd on loopback ports.
        __darwinAllowLocalNetworking = true;

        env = {
          CLOUDFLARE_CF_FETCH_ENABLED = "false";
          WRANGLER_SEND_METRICS = "false";
          CI = "true";
        };

        dontConfigure = true;

        buildPhase = ''
          runHook preBuild
          export HOME=$(mktemp -d)
          cp -R ${deps}/node_modules node_modules
          cp -R ${deps}/packages/evidence-worker/node_modules packages/evidence-worker/node_modules
          chmod -R u+w node_modules packages/evidence-worker/node_modules
          ${lib.optionalString isLinux ''
            # The prebuilt workerd's PT_INTERP (/lib64/ld-linux-x86-64.so.2)
            # does not exist in the Linux build sandbox.
            shopt -s nullglob
            for binary in node_modules/.bun/@cloudflare+workerd-linux-*/node_modules/@cloudflare/workerd-linux-*/bin/workerd; do
              autoPatchelf "$binary"
            done
          ''}
          cd packages/evidence-worker
          node ./node_modules/.bin/tsc -p .
          node ./node_modules/.bin/tsc -p test
          node ./node_modules/.bin/vitest run
          runHook postBuild
        '';

        installPhase = ''
          touch $out
        '';

        meta.description = "behavioural check: evidence Worker routing, headers and R2 reads in workerd, plus strict typecheck";
      };
    };
}
