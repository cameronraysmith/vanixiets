# checks.x86_64-linux.ntfy-tls-verification (CAM-87): no ntfy.zt client in the
# repository skips certificate verification.
#
# The tree is every .sh, .bash, .nix, .py, .ts and .js file under modules/ and
# pkgs/. Clause A fails on a curl or wget command line, continuations joined,
# carrying -k, --insecure or a short-option cluster containing k, in a file
# naming ntfy.zt; its value sources are the file's text and curl's option
# grammar (curl-8_22_0 docs/cmdline-opts/insecure.md). Clause B fails when a
# declared client is missing or passes no --cacert; its sources are the
# declared list and the file. Clause C fails when a file naming ntfy.zt and
# invoking curl or wget is in no list; its sources are the lists and the tree.
# Clause C counts a mention of curl or wget anywhere in a file, comments
# included, so a file that only mentions one beside ntfy.zt is declared a
# non-client with its reason.
# Each mutant changes one copy of the tree and runs only its clause.
{ lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      tree = lib.fileset.toSource {
        root = ../..;
        # fileFilter takes a path, so each directory is filtered and the results joined.
        fileset = lib.fileset.unions (
          map
            (lib.fileset.fileFilter (
              f:
              lib.any f.hasExt [
                "sh"
                "bash"
                "nix"
                "py"
                "ts"
                "js"
              ]
            ))
            [
              ../../modules
              ../../pkgs
            ]
        );
      };
      clients = pkgs.writeText "ntfy-clients" ''
        pkgs/by-name/ntfy-send/ntfy-send.sh
      '';
      nonclients = pkgs.writeText "ntfy-nonclients" ''
        modules/machines/nixos/cinnabar/zt-dns.nix	serves the name; its curl reaches the ZeroTier controller on localhost
        modules/nixos/fleet-alert.nix	the dead-man's curl reaches ntfy's own listener over HTTP; posts go through ntfy-send
        pkgs/by-name/ntfy-send/package.nix	builds the client and names curl's path
        modules/vm-tests/caddy-root-from-vars.nix	a VM test whose curl verifies with --cacert against a root made in the test, inside the VM
        modules/lib/observability-notify-run.nix	a comment on how ntfy-send posts; the notifier posts through ntfy-send and runs no curl
      '';
      exempt = pkgs.writeText "ntfy-exempt" ''
        pkgs/by-name/ntfy-send/test-token-transport.nix	a recording curl stub
        pkgs/by-name/ntfy-send/test-tls-verification.nix	holds the -k mutant
        modules/checks/ntfy-tls-verification.nix	this check and its mutants
        modules/checks/ntfy-tls-verification/scan.bash	this check's scanner
      '';
      scan = ./ntfy-tls-verification/scan.bash;
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        ntfy-tls-verification =
          pkgs.runCommand "ntfy-tls-verification"
            {
              nativeBuildInputs = [
                pkgs.gawk
                pkgs.gnugrep
              ];
            }
            ''
              set -uo pipefail
              # scanTree TREE CLAUSE…: the scanner's order is TREE CLIENTS NONCLIENTS EXEMPT CLAUSE….
              scanTree() { local t=$1; shift; ${pkgs.bash}/bin/bash ${scan} "$t" ${clients} ${nonclients} ${exempt} "$@"; }
              scanTree ${tree} A B C || { echo "FAIL: the repository's tree"; exit 1; }
              echo "ok: the repository's tree passes A, B and C"

              # mutant NAME CLAUSE EXPECTED EDIT: copies the tree, applies EDIT in it,
              # runs only CLAUSE, and requires a failure whose output contains EXPECTED.
              mutant() {
                # `found`, not `out`, which names this derivation's output.
                local name=$1 clause=$2 expected=$3 edit=$4 t found
                t=$(mktemp -d)
                cp -r ${tree}/. "$t"
                chmod -R u+w "$t"
                (cd "$t" && eval "$edit")
                if found=$(scanTree "$t" "$clause"); then
                  echo "FAIL: mutant $name passed clause $clause"; exit 1
                fi
                grep -qF -- "$expected" <<< "$found" || { echo "FAIL: mutant $name: $found"; exit 1; }
                echo "mutant $name rejected"
              }
              ns=pkgs/by-name/ntfy-send/ntfy-send.sh
              mutant insecureShort A "$ns" "sed -i 's/--cacert \"\$NTFY_CACERT\"/-k/' $ns"
              mutant insecureCluster A "$ns" "sed -i 's/ -sf --cacert/ -sfk --cacert/' $ns"
              mutant insecureLong A "$ns" "sed -i 's/ -sf --cacert/ -sf --insecure --cacert/' $ns"
              mutant insecureContinued A modules/x/post.sh "mkdir -p modules/x && printf 'curl \\\\\n  -k \\\\\n  https://ntfy.zt/x\n' > modules/x/post.sh"
              mutant clientMissing B "is missing" "rm $ns"
              mutant cacertDropped B "passes no --cacert" "sed -i 's/ --cacert \"\$NTFY_CACERT\"//' $ns"
              mutant undeclaredClient C modules/x/post.sh "mkdir -p modules/x && printf 'curl --cacert ca https://ntfy.zt/x\n' > modules/x/post.sh"
              touch $out
            '';
      };
    };
}
