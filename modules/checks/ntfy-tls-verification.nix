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
# The same check judges flake.lib.caddyRootCheck, which cinnabar runs weekly,
# against chains served by openssl s_server on loopback (design D6).
{ config, lib, ... }:
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
                pkgs.openssl
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

              # Root-check legs (design D6): a root, an intermediate under it and a leaf
              # for ntfy.zt, served by openssl s_server on loopback; validities relative to
              # this build's clock. The values related are the served chain against the
              # bundle, and the bundle's first root's notAfter against the clock.
              mkroot() {
                openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout "$1.key" -sha256 -days "$2" \
                  -subj "/CN=$1" -addext basicConstraints=critical,CA:TRUE,pathlen:1 -addext keyUsage=critical,keyCertSign,cRLSign -out "$1.crt" 2>/dev/null
                openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout "$1-int.key" -subj "/CN=$1 int" -out "$1-int.csr" 2>/dev/null
                printf 'basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n' > int.ext
                openssl x509 -req -in "$1-int.csr" -CA "$1.crt" -CAkey "$1.key" -CAcreateserial -days 30 -extfile int.ext -out "$1-int.crt" 2>/dev/null
                openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout "$1-leaf.key" -subj "/CN=ntfy.zt" -out "$1-leaf.csr" 2>/dev/null
                printf 'subjectAltName=DNS:ntfy.zt\nextendedKeyUsage=serverAuth\n' > leaf.ext
                openssl x509 -req -in "$1-leaf.csr" -CA "$1-int.crt" -CAkey "$1-int.key" -CAcreateserial -days 7 -extfile leaf.ext -out "$1-leaf.crt" 2>/dev/null
              }
              cd "$(mktemp -d)"
              mkroot r1 400; mkroot r2 400; mkroot r3 100
              cat r1.crt r2.crt > overlap.crt
              # serve ROOT PORT: serves ROOT's leaf with its intermediate on 127.0.0.1:PORT.
              serve() { openssl s_server -quiet -accept "127.0.0.1:$2" -cert "$1-leaf.crt" -key "$1-leaf.key" -cert_chain "$1-int.crt" -www & sleep 0.5; }
              serve r1 18441; serve r2 18442; serve r3 18443
              # LEG_CA and LEG_ADDR, not BUNDLE and CONNECT, which shellcheck's SC2153
              # reads as misspellings of the script's own bundle and connect.
              check=${
                lib.getExe (
                  config.flake.lib.caddyRootCheck pkgs {
                    bundle = "$LEG_CA";
                    connect = "$LEG_ADDR";
                    servername = "ntfy.zt";
                  }
                )
              }
              # leg NAME BUNDLE PORT EXPECTED [SCRIPT]: EXPECTED is ok or a message fragment.
              leg() {
                local name=$1 bundle=$2 port=$3 expected=$4 script=''${5:-$check} found rc=0
                found=$(LEG_CA=$bundle LEG_ADDR=127.0.0.1:$port bash "$script" 2>&1) || rc=$?
                if [ "$expected" = ok ]; then [ "$rc" = 0 ] || { echo "FAIL $name: exit $rc: $found"; return 1; }
                else [ "$rc" != 0 ] && grep -qF -- "$expected" <<< "$found" || { echo "FAIL $name: exit $rc: $found"; return 1; }; fi
                echo "ok: $name"
              }
              leg servedHeld r1.crt 18441 ok || exit 1
              leg servedInOverlap overlap.crt 18442 ok || exit 1
              leg servedDrifted r1.crt 18442 "does not verify" || exit 1
              leg rootExpiring r3.crt 18443 "expires" || exit 1
              sed 's/^verified=0$/verified=1/' "$check" > verificationSkipped
              if leg servedDrifted r1.crt 18442 "does not verify" verificationSkipped; then echo "FAIL: mutant verificationSkipped passed"; exit 1; fi
              echo "mutant verificationSkipped rejected"
              sed 's/openssl x509 -checkend/true/' "$check" > expirySkipped
              if leg rootExpiring r3.crt 18443 "expires" expirySkipped; then echo "FAIL: mutant expirySkipped passed"; exit 1; fi
              echo "mutant expirySkipped rejected"
              touch $out
            '';
      };
    };
}
