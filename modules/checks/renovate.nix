# Schema validation for .github/renovate.json.
#
# Renovate config errors are otherwise only discovered by the hosted bot, which
# reports them as a "Config Warning" issue on the repository after a push has
# already landed. `renovate-config-validator` ships in the same nixpkgs
# `renovate` derivation as the bot itself, so the schema this validates is the
# schema the running version enforces.
#
# Scope, stated plainly so no one over-trusts a green check: this is a SCHEMA
# check. It catches unknown option names, wrong types, malformed regex, and
# configs needing migration (`--strict`). It cannot see whether a rule means
# what its author intended -- a `matchPackageNames` naming the wrong owner, a
# customManager regex capturing a branch name where a version belongs, or a
# package group that is simply missing are all valid config and all pass here.
# None of this repository's actual renovate defects would have been caught by
# this check.
#
# Hermetic: the validator resolves nothing over the network. `validateConfig`
# checks the config tree against the option definitions compiled into the
# binary; `extends` preset resolution is a separate step that only a real
# renovate run performs. Verified by building this check in the nix sandbox,
# which has no network.
#
# The config is copied to `.github/renovate.json` in the build directory and
# the validator is invoked with no file arguments so it auto-detects it. That
# path matters: `getConfigFileNames()` lists `.github/renovate.json` as a
# default location and auto-detected files are validated as `repo` config,
# whereas a file passed as an argument is treated as *global* self-hosted
# config unless `--no-global` is also given (lib/config-validator.ts). Our file
# is repo config, so auto-detection is the honest invocation.
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.renovate-config =
        pkgs.runCommand "renovate-config"
          {
            nativeBuildInputs = [ pkgs.renovate ];
            passthru.meta.description = "Validate .github/renovate.json against the renovate config schema";
          }
          ''
            mkdir -p .github
            cp ${../../.github/renovate.json} .github/renovate.json

            # The validator writes nothing, but node tooling resolves $HOME.
            export HOME="$PWD/home"
            mkdir -p "$HOME"

            echo "Validating .github/renovate.json with renovate ${pkgs.renovate.version}..."
            renovate-config-validator --strict

            echo "OK: renovate config is schema-valid (semantics are not checked)"
            touch $out
          '';
    };
}
