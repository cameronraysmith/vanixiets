# mkEvalCheck: thin runCommand wrapper around `nix-unit` for direct
# expression evaluation, bypassing the upstream nix-unit-flake-parts
# module's `--flake` + `--override-input` machinery.
#
# Why we don't use `--flake`: the upstream wrapper drives
# `nix-unit --override-input self <store-path> --flake <self>#tests.systems.<sys>`
# inside the sandbox. nix then re-resolves every input in the lockfile
# (visible as 25 "Updated input ..." log lines per run) and re-evaluates
# the full dendritic flake graph (1132 files in this repo) before any
# assertion runs. The 3+ minute floor we observed lived entirely in that
# preamble; the assertions themselves complete in milliseconds.
#
# Why this is enough: our genuine nix-unit tests target pure nix
# expressions (lib helpers, submodule outputs, HM module instantiation
# against a stub). They don't need `self` access or full flake context.
# `nix-unit --eval-store "$HOME" <test-file>` evaluates the file as a
# plain nix expression that returns an attrset of test cases, which is
# precisely the shape nix-unit was designed for. This is the
# `flake-compat/dev/config.nix` pattern (lines 58-66), not clan-core's.
#
# Tests requiring full flake evaluation belong as runCommand JSON-diff
# checks under `modules/checks/structure/`, not as nix-unit tests.
{ ... }:
{
  flake.lib.mkEvalCheck =
    pkgs:
    {
      name,
      testFile,
    }:
    pkgs.runCommand "evalCheck-${name}"
      {
        nativeBuildInputs = [ pkgs.nix-unit ];
        meta.description = "nix-unit eval check: ${name}";
      }
      ''
        export HOME="$(realpath .)"
        nix-unit \
          --eval-store "$HOME" \
          --extra-experimental-features 'nix-command flakes' \
          ${testFile}
        touch $out
      '';
}
