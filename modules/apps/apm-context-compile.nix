# Composes this repo's agent-context-* apm packages into the repo-root
# AGENTS.md (+ a CLAUDE.md pointer). Mirrors the apm-skills-install +
# co-located .sh sidecar convention.
{ ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      packages.apm-context-compile = pkgs.writeShellApplication {
        name = "apm-context-compile";
        runtimeInputs = [
          pkgs.apm
          pkgs.git # repo root resolution
          pkgs.yq-go
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
        ];
        text = builtins.readFile ./apm-context-compile.sh;

        # Build locally; never ask a remote cache for this path.
        #
        # This derivation is a shell script wrapper: building it is a
        # `printf` plus a shellcheck run, cheaper than a single HTTPS
        # round trip. Yet nothing but this repository could ever have
        # built it, so every substituter query is guaranteed to miss.
        #
        # `writeTextFile` and its thin wrappers (`writeShellScriptBin`,
        # `writeScriptBin`, ...) default to `allowSubstitutes ? false`
        # and `preferLocalBuild ? true` for exactly this reason.
        # `writeShellApplication` is the odd one out in nixpkgs: it
        # passes `allowSubstitutes = true; preferLocalBuild = false;`
        # to `writeTextFile` explicitly, hard-coded rather than as a
        # function argument, so it cannot be turned off by an argument
        # to `writeShellApplication` itself. `derivationArgs` is the
        # documented escape hatch: `writeTextFile` merges it last
        # (`// removeAttrs derivationArgs [ "meta" "passthru" ]`), so
        # these two win over the hard-coded pair.
        #
        # Without this, entering the devshell after any input bump that
        # moves this output hash stalls ~60s (`stalled-download-timeout`)
        # while the nine configured caches are asked, one narinfo request
        # each, about a path none of them has heard of. This package is
        # reached from `modules/devshells/default.nix`'s shellHook via
        # `lib.getExe`, so it must be realised before the shell exists.
        derivationArgs = {
          preferLocalBuild = true;
          allowSubstitutes = false;
        };
      };

      apps.apm-context-compile = {
        type = "app";
        program = lib.getExe config.packages.apm-context-compile;
      };
    };
}
