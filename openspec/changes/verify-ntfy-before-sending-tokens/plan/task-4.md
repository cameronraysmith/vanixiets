### Task 4: The verifying client

Implements `tasks.md` 4.1–4.7 (design D1–D5; O1–O4; FAI `ntfy-send verifies ntfy.zt against caddy's root and fails closed`, `No ntfy.zt client in the repository skips verification`, `The alerter token travels only as a file`; FA `A host posts to the notification service only over a verified connection`).
It starts after pull request 1 merges and Task 3 has deployed cinnabar, so RV exists on `main@origin`.
Order inside the task: the TLS test and the token test go red (Steps 1, 2), the script and package turn them green (Step 3), the scan goes red on the hooks (Step 4), the hooks turn it green (Step 5).

**Files:**
- Create: `pkgs/by-name/ntfy-send/test-tls-verification.nix`, `modules/checks/ntfy-tls-verification.nix`, `modules/checks/ntfy-tls-verification/scan.bash`.
- Modify: `pkgs/by-name/ntfy-send/ntfy-send.sh`, `pkgs/by-name/ntfy-send/package.nix`, `pkgs/by-name/ntfy-send/test-token-transport.nix`, `modules/checks/package-tests.nix`, `modules/home/tools/hooks/notify-permission-prompt.sh`, `modules/home/tools/hooks/notify-permission-wait.sh`, `modules/home/tools/hooks/default.nix`, `modules/lib/observability-notify-run.nix`, `modules/clan/services/otel-collector/README.md`.
- Create (git-ignored): `logs/cam87-evidence/4.<n>-*.log`.

**Interfaces:**
- Consumes: RV, `vars/per-machine/cinnabar/caddy-root-ca/root.crt/value`, committed by Task 2; the root pin's `curl`, `openssl` and `python3`.
- Produces: the package, test, hook and check names of plan "Interface contract".

- [ ] **Step 1: The TLS test, red (4.1)**

Create `pkgs/by-name/ntfy-send/test-tls-verification.nix`:

```nix
# passthru.tests.tls-verification (CAM-87): ntfy-send verifies ntfy.zt against
# the CA file in NTFY_CACERT. The real curl and the script meet a loopback TLS
# server for ntfy.zt, reached through ntfy-send's pass-through
# `--connect-to ntfy.zt:443:127.0.0.1:<port>`, whose leaf a CA made here
# ("other") signed. Under caddy's root the source script and the built wrapper
# are refused (curl exit 60) and the server records nothing; under "other",
# and under a file holding caddy's root then "other", the post is accepted.
# The mutant replaces --cacert with -k and runs only the first case, which it
# must pass.
{
  lib,
  runCommand,
  bash,
  curl,
  openssl,
  python3,
  ntfySend,
  caddyRootCa,
}:
runCommand "ntfy-send-test-tls-verification"
  {
    nativeBuildInputs = [
      openssl
      python3
    ];
    __darwinAllowLocalNetworking = true;
  }
  ''
    set -euo pipefail
    work=$(mktemp -d)
    cd "$work"

    openssl ecparam -name prime256v1 -genkey -noout -out other.key
    openssl req -x509 -new -key other.key -sha256 -days 30 -subj "/CN=ntfy-send test other root" \
      -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign -out other.crt
    openssl ecparam -name prime256v1 -genkey -noout -out leaf.key
    openssl req -new -key leaf.key -subj "/CN=ntfy.zt" -out leaf.csr
    printf 'subjectAltName=DNS:ntfy.zt\nextendedKeyUsage=serverAuth\n' > leaf.ext
    openssl x509 -req -in leaf.csr -CA other.crt -CAkey other.key -CAcreateserial -days 30 -sha256 -extfile leaf.ext -out leaf.crt
    cat ${caddyRootCa} other.crt > bundle.crt

    cat > server.py <<'PY'
    import http.server, ssl, sys
    received = sys.argv[1]
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            with open(received, "ab") as f:
                f.write(body + b"\n")
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"event":"message"}\n')
        def log_message(self, *args):
            pass
    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain("leaf.crt", "leaf.key")
    server.socket = context.wrap_socket(server.socket, server_side=True)
    with open("port.tmp", "w") as f:
        f.write(str(server.server_address[1]))
    import os
    os.rename("port.tmp", "port")
    server.serve_forever()
    PY
    python3 server.py "$work/received" &
    server=$!
    trap 'kill $server' EXIT
    for _ in $(seq 100); do [ -s port ] && break; sleep 0.1; done
    port=$(cat port)
    export NTFY_CURL_BIN=${lib.getExe curl}

    # post WHO [CA]: WHO is `built` or a script path; CA, given with a script,
    # is NTFY_CACERT. Sets $rc and $got.
    post() {
      local who=$1 ca=''${2:-}
      : > received
      rc=0
      if [ "$who" = built ]; then
        ${lib.getExe ntfySend} hello t --connect-to "ntfy.zt:443:127.0.0.1:$port" > /dev/null 2>&1 || rc=$?
      else
        NTFY_CACERT=$ca ${bash}/bin/bash "$who" hello t --connect-to "ntfy.zt:443:127.0.0.1:$port" > /dev/null 2>&1 || rc=$?
      fi
      got=$(cat received)
    }

    foreignRefusedSource() {
      post "$1" ${caddyRootCa}
      [ "$rc" = 60 ] && [ -z "$got" ] || { echo "FAIL foreignRefusedSource: exit $rc, received '$got'"; return 1; }
      echo "ok: foreignRefusedSource"
    }

    foreignRefusedSource ${./ntfy-send.sh}

    post built
    [ "$rc" = 60 ] && [ -z "$got" ] || { echo "FAIL foreignRefusedBuilt: exit $rc, received '$got'"; exit 1; }
    echo "ok: foreignRefusedBuilt"

    post ${./ntfy-send.sh} "$work/other.crt"
    [ "$rc" = 0 ] && [ "$got" = hello ] || { echo "FAIL ownAccepted: exit $rc, received '$got'"; exit 1; }
    echo "ok: ownAccepted"

    post ${./ntfy-send.sh} "$work/bundle.crt"
    [ "$rc" = 0 ] && [ "$got" = hello ] || { echo "FAIL bundleAccepted: exit $rc, received '$got'"; exit 1; }
    echo "ok: bundleAccepted"

    ${bash}/bin/bash ${./ntfy-send.sh} --help > help.txt
    grep -q '^  NTFY_CACERT ' help.txt || { echo "FAIL help: NTFY_CACERT undocumented"; exit 1; }
    if grep -qi 'endpoint security' help.txt; then echo "FAIL help: endpoint-security claim"; exit 1; fi
    echo "ok: help"

    substitute ${./ntfy-send.sh} mutant.sh --replace-fail '--cacert "$NTFY_CACERT"' '-k'
    if foreignRefusedSource "$work/mutant.sh"; then
      echo "FAIL: mutant insecure was accepted"
      exit 1
    fi
    echo "mutant insecure rejected"
    touch "$out"
  ''
```

Declare it in `modules/checks/package-tests.nix`:

```nix
        ntfy-send = [
          "tls-verification"
          "token-transport"
        ];
```

and add it to `package.nix`'s `passthru.tests` in the shape Step 3 gives, but with the current script, so the test builds against the `-sfk` script.
Run `jj st --no-pager >/dev/null`, then:

```bash
nix build .#checks.x86_64-linux.package-ntfy-send-test-tls-verification -L --option builders "$(grep 930f /etc/nix/machines | head -1)" 2>&1 | tee "logs/cam87-evidence/4.1-red-$(/bin/date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: FAIL at `foreignRefusedSource: exit 0, received 'hello'`, because `-k` accepts the foreign server; if the build fails earlier (the server not starting, a missing tool), fix the test before going on, since that is not the red this step wants.

- [ ] **Step 2: The token test, red (4.2)**

In `pkgs/by-name/ntfy-send/test-token-transport.nix`, set `export NTFY_CACERT=/ca` beside `NTFY_CURL_BIN`, a path the stub never reads, and change the three expected lists:

```bash
    [ "$(cat "$REC/argv")" = "$(printf '%s\n' -sf --cacert /ca -m 5 -H @-)"$'\n'"$caller" ] || { echo "FAIL: token set: argv is not -H @- before the caller's arguments"; return 1; }
    [ "$(cat "$REC/argv")" = "$(printf '%s\n' -sf --cacert /ca -m 5)"$'\n'"$caller" ] || { echo "FAIL: token unset: argv changed"; return 1; }
    [ "$(cat "$REC/argv")" = "$(printf '%s\n' -sf --cacert /ca -m 5)"$'\n'"$caller" ] || { echo "FAIL: token empty: argv changed"; return 1; }
```

Add, after the argv mutant, the cases `caUnset` and `caEmpty` and the mutant `cacertGuardDropped`; the stub records argv only when curl runs, so "before curl runs" is observed as no `$REC/argv`:

```bash
  # caUnset, caEmpty SCRIPT: without a CA file the script exits non-zero
  # before curl runs, so the stub records no argv.
  caUnset() {
    run "$1" -u NTFY_CACERT
    [ "$status" != 0 ] && [ ! -e "$REC/argv" ] || { echo "FAIL: caUnset: exit $status, argv $(cat "$REC/argv" 2>/dev/null | tr '\n' ' ')"; return 1; }
    echo "ok: caUnset: exit $status before curl"
  }
  caEmpty() {
    run "$1" NTFY_CACERT=
    [ "$status" != 0 ] && [ ! -e "$REC/argv" ] || { echo "FAIL: caEmpty: exit $status, argv $(cat "$REC/argv" 2>/dev/null | tr '\n' ' ')"; return 1; }
    echo "ok: caEmpty: exit $status before curl"
  }
  caUnset ${./ntfy-send.sh}
  caEmpty ${./ntfy-send.sh}

  # cacertGuardDropped: the script without its NTFY_CACERT guard runs curl with
  # an empty --cacert, which only the guard stops; set -u alone stops the unset
  # case, so the mutant runs only caEmpty.
  substitute ${./ntfy-send.sh} "$work/guardless.sh" \
    --replace-fail ': "''${NTFY_CACERT:?ntfy-send: NTFY_CACERT names no CA file}"' ':'
  if caEmpty "$work/guardless.sh"; then
    echo "FAIL: mutant cacertGuardDropped passed caEmpty"
    exit 1
  fi
  echo "mutant cacertGuardDropped rejected"
```

The test's header comment gains one sentence stating the two cases and the mutant.
Run `nix build .#checks.x86_64-linux.package-ntfy-send-test-token-transport -L --option builders "$(grep 930f /etc/nix/machines | head -1)"`.
Expected: FAIL at `token set: argv is not -H @- before the caller's arguments`; the new cases and their mutant run after the argv cases, so they are first judged in Step 3.

- [ ] **Step 3: The script and package, green (4.3)**

Replace `pkgs/by-name/ntfy-send/ntfy-send.sh` with:

```bash
#!/usr/bin/env bash
# Send push notification via ntfy.zt, verifying its certificate
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'HELP'
Send push notification via ntfy.zt

Usage: ntfy-send MESSAGE [TOPIC] [CURL_ARGS...]

Arguments:
  MESSAGE     Notification body text (required)
  TOPIC       ntfy topic (default: local hostname)
  CURL_ARGS   Extra curl arguments (e.g. -H "Priority: high")

Environment:
  NTFY_TOKEN_FILE  File holding an ntfy access token; when set and non-empty,
                   the token is sent as "Authorization: Bearer" on curl's
                   stdin (-H @-), never on a command line. fleet-* topics
                   need it; host topics accept anonymous posts.
  NTFY_CACERT      The CA file ntfy.zt's certificate must chain to. The
                   package sets it to caddy's root, the public value of
                   cinnabar's clan vars caddy-root-ca.
                   ntfy-send never skips certificate verification, and
                   exits before posting when NTFY_CACERT is unset.

Examples:
  ntfy-send "build complete"
  ntfy-send "deploy finished" stibnite
  ntfy-send "alert" stibnite -H "Priority: urgent" -H "Tags: warning"
  NTFY_TOKEN_FILE=/run/secrets/vars/shared/ntfy-alerter/token ntfy-send "probe" fleet-acceptance
HELP
    exit 0
    ;;
esac

: "${NTFY_CACERT:?ntfy-send: NTFY_CACERT names no CA file}"
msg="${1:?usage: ntfy-send MESSAGE [TOPIC] [CURL_ARGS...]}"
topic="${2:-$(hostname -s)}"
shift 2 2>/dev/null || shift $#
if [ -n "${NTFY_TOKEN_FILE:-}" ]; then
  # $(< file) and printf are bash builtins, so the token is on no argv.
  token=$(< "$NTFY_TOKEN_FILE")
  printf 'Authorization: Bearer %s\n' "$token" |
    "${NTFY_CURL_BIN:-curl}" -sf --cacert "$NTFY_CACERT" -m 5 -H @- "$@" -d "$msg" "https://ntfy.zt/$topic"
else
  "${NTFY_CURL_BIN:-curl}" \
    -sf --cacert "$NTFY_CACERT" -m 5 "$@" -d "$msg" "https://ntfy.zt/$topic"
fi
```

Replace `pkgs/by-name/ntfy-send/package.nix` with:

```nix
# ntfy-send: post a push notification to the fleet's ntfy server (ntfy.zt).
# One source for every delivery: the home-manager tools command installs it,
# system units and launchd jobs run it, and the agent permission hooks post
# through it.
#
# The preamble exports NTFY_CURL_BIN=curl, the curl from runtimeInputs on every
# platform, and NTFY_CACERT, the store copy of caddy's root, the public value
# of cinnabar's clan vars caddy-root-ca
# (vars/per-machine/cinnabar/caddy-root-ca/root.crt/value), which every post's
# --cacert names, so ntfy-send verifies ntfy.zt's certificate and posts
# nothing to a server that cannot present a chain to that root. The file may
# hold two roots while a rotation overlaps them (the fleet observability
# runbook, "caddy's root").
#
# NTFY_TOKEN_FILE, when set and non-empty, names a file holding an ntfy access
# token, such as the `alerter` token that fleet-* topics require. The script
# reads it with bash's $(< file) and prints `Authorization: Bearer <token>` with
# the printf builtin into curl's stdin, which curl reads with `-H @-`, so the
# token is on no process's argv. Unset, the post is anonymous, which host
# topics accept. passthru.tests.token-transport runs the source script against
# a recording curl stub, with a mutant that passes the header on argv;
# passthru.tests.tls-verification runs it and the built wrapper against a
# loopback TLS server, with a mutant that passes -k.
{
  lib,
  curl,
  callPackage,
  writeShellApplication,
  caddyRootCa ? ../../../vars/per-machine/cinnabar/caddy-root-ca/root.crt/value,
}:
let
  ntfy-send = writeShellApplication {
    name = "ntfy-send";
    runtimeInputs = [ curl ];
    text = ''
      export NTFY_CURL_BIN=curl
      export NTFY_CACERT=${caddyRootCa}
      ${builtins.readFile ./ntfy-send.sh}
    '';
    passthru.tests = {
      token-transport = callPackage ./test-token-transport.nix { };
      tls-verification = callPackage ./test-tls-verification.nix {
        ntfySend = ntfy-send;
        inherit caddyRootCa;
      };
    };
    meta = {
      description = "Send push notification via ntfy.zt, verifying its certificate against caddy's root";
      license = lib.licenses.mit;
      mainProgram = "ntfy-send";
    };
  };
in
ntfy-send
```

Run `jj st --no-pager >/dev/null`, then build and evaluate:

```bash
{
  nix build .#checks.x86_64-linux.package-ntfy-send-test-tls-verification -L --option builders "$(grep 930f /etc/nix/machines | head -1)"
  nix build .#checks.x86_64-linux.package-ntfy-send-test-token-transport -L --option builders "$(grep 930f /etc/nix/machines | head -1)"
  nix build .#checks.aarch64-darwin.package-ntfy-send-test-tls-verification -L
  nix build .#checks.aarch64-darwin.package-ntfy-send-test-token-transport -L
  w=$(nix build --print-out-paths --no-link .#packages.aarch64-darwin.ntfy-send)/bin/ntfy-send
  grep -E '^export NTFY_(CURL_BIN|CACERT)=' "$w"
  cmp "$(sed -n 's/^export NTFY_CACERT=//p' "$w")" vars/per-machine/cinnabar/caddy-root-ca/root.crt/value && echo "NTFY_CACERT equals RV"
  nix build .#checks.x86_64-linux.fleet-alert -L --option builders "$(grep 930f /etc/nix/machines | head -1)"
  nix eval --raw .#nixosConfigurations.magnetite.config.system.build.toplevel.drvPath
} 2>&1 | tee "logs/cam87-evidence/4.3-green-$(/bin/date -u +%Y%m%dT%H%M%SZ).log"
```

The two `aarch64-darwin` builds run on stibnite.
Expected: every case prints `ok:`, `mutant insecure rejected`, the token test's argv mutant rejected and `mutant cacertGuardDropped rejected` on both systems; the wrapper exports `NTFY_CURL_BIN=curl` and an `NTFY_CACERT` equal to RV; `fleet-alert` passes and magnetite's evaluation succeeds, so R9.5's assertions still read a 5 s post timeout.
Record the cost of the two package tests and of `fleet-alert` after the change by the plan's method.
Commit: "ntfy-send: verify ntfy.zt's certificate against caddy's root".

- [ ] **Step 4: The client scan, red (4.4)**

Create `modules/checks/ntfy-tls-verification/scan.bash`:

```bash
# scan.bash TREE CLIENTS NONCLIENTS EXEMPT CLAUSE...
# Judges the source tree TREE for ntfy.zt clients. CLIENTS, NONCLIENTS and
# EXEMPT are files listing tree-relative paths, one per line (NONCLIENTS as
# "<path>\t<reason>"). CLAUSE is any of A, B, C. Prints "FAIL <clause>: …" for
# each finding and exits 1 if any clause failed.
set -uo pipefail
tree=$1 clients=$2 nonclients=$3 exempt=$4
shift 4
cd "$tree"
fail=0
named=$(grep -rlF --include='*.sh' --include='*.bash' --include='*.nix' --include='*.py' --include='*.ts' --include='*.js' 'ntfy.zt' modules pkgs | LC_ALL=C sort)
invokes='(^|[^A-Za-z0-9_-])(curl|wget|CURL_BIN)([^A-Za-z0-9_]|$)'
insecure='(^|[[:space:]"'"'"'])(-[A-Za-z]*k[A-Za-z]*|--insecure)([[:space:]"'"'"']|$)'
# logical FILE: prints "FILE:LINE: <command line with continuations joined>".
logical() {
  awk '{ line = $0; if (sub(/\\[[:space:]]*$/, "", line)) { buf = buf line " "; next } print FILENAME ":" FNR ": " buf line; buf = "" }' "$1"
}
listed() { cut -f1 "$1" | grep -qxF "$2"; }
for clause in "$@"; do
  case $clause in
    A)
      for f in $named; do
        listed "$exempt" "$f" && continue
        hits=$(logical "$f" | grep -E "$invokes" | grep -E -- "$insecure")
        [ -z "$hits" ] || { printf 'FAIL A: %s\n' "$hits"; fail=1; }
      done ;;
    B)
      while IFS= read -r c; do
        [ -n "$c" ] || continue
        if [ ! -f "$c" ]; then echo "FAIL B: declared client $c is missing"; fail=1
        elif ! grep -qF -- '--cacert' "$c"; then echo "FAIL B: declared client $c passes no --cacert"; fail=1; fi
      done < "$clients" ;;
    C)
      for f in $named; do
        grep -qE "$invokes" "$f" || continue
        listed "$clients" "$f" || listed "$nonclients" "$f" || listed "$exempt" "$f" || { echo "FAIL C: $f names ntfy.zt and invokes curl or wget but is not declared"; fail=1; }
      done ;;
  esac
done
exit $fail
```

Create `modules/checks/ntfy-tls-verification.nix`:

```nix
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
        fileset = lib.fileset.fileFilter (
          f:
          lib.any f.hasExt [
            "sh"
            "bash"
            "nix"
            "py"
            "ts"
            "js"
          ]
        ) (lib.fileset.unions [ ../../modules ../../pkgs ]);
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
                local name=$1 clause=$2 expected=$3 edit=$4 t
                t=$(mktemp -d)
                cp -r ${tree}/. "$t"
                chmod -R u+w "$t"
                (cd "$t" && eval "$edit")
                if out=$(scanTree "$t" "$clause"); then
                  echo "FAIL: mutant $name passed clause $clause"; exit 1
                fi
                grep -qF -- "$expected" <<< "$out" || { echo "FAIL: mutant $name: $out"; exit 1; }
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
```

The step adjusts the quoting of the `sed` and `printf` edits until each mutant applies exactly its change, verified by printing the edited line once while writing it; the final text keeps one mutant per clause failure as listed.
Run `jj st --no-pager >/dev/null`, record the check's cost by the plan's method, and build:

```bash
nix build .#checks.x86_64-linux.ntfy-tls-verification -L --option builders "$(grep 930f /etc/nix/machines | head -1)" 2>&1 | tee "logs/cam87-evidence/4.4-red-$(/bin/date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `FAIL: the repository's tree`, with `FAIL A:` lines naming `modules/home/tools/hooks/notify-permission-prompt.sh:45` and `modules/home/tools/hooks/notify-permission-wait.sh:17`, and `FAIL C:` lines naming both files and `modules/home/tools/hooks/default.nix`, which names `ntfy.zt` and lists `curl` in the two hooks' `runtimeInputs` until Step 5.
To see the mutants before the hooks change, temporarily run the mutant block over a tree whose three hook files named above are removed in the copy, and confirm each prints `mutant <name> rejected`; that temporary edit is not committed.
If the cost exceeds 536,870,912 B, replace `tree` with `self`'s source (`"${self}"`, from the module's `self` argument) and record the cost again.

- [ ] **Step 5: The hooks through ntfy-send, green (4.5)**

In `modules/home/tools/hooks/notify-permission-prompt.sh`, replace lines 42-50 with:

```bash
# Send notification to ntfy.zt through ntfy-send, which verifies the server's
# certificate and times out after 5 seconds; best-effort, never fail the hook.
ntfy-send "$MESSAGE" "$NTFY_TOPIC" \
  -H "Title: Permission: ${TOOL_NAME}" \
  -H "Priority: default" \
  -H "Tags: lock,${REPO_NAME}" 2>/dev/null || true
```

In `modules/home/tools/hooks/notify-permission-wait.sh`, replace lines 16-22 with:

```bash
# Best-effort delivery through ntfy-send; never fail the caller.
ntfy-send "$MESSAGE" "$NTFY_TOPIC" \
  -H "Title: Permission: ${TOOL_NAME}" \
  -H "Priority: default" \
  -H "Tags: lock,${REPO_NAME}" &>/dev/null || true
```

In `modules/home/tools/hooks/default.nix`, replace `curl` with `pkgs.ntfy-send` in the `runtimeInputs` of `notify-permission-wait` (the `with pkgs;` list becomes `ntfy-send`) and `notify-permission-prompt`, and add `pkgs.ntfy-send` to `gate-dangerous-commands`'s.
Run `jj st --no-pager >/dev/null`, then:

```bash
{
  nix build .#checks.x86_64-linux.ntfy-tls-verification -L --option builders "$(grep 930f /etc/nix/machines | head -1)"
  nix build .#checks.x86_64-linux.hook-gate-dangerous-commands -L --option builders "$(grep 930f /etc/nix/machines | head -1)"
  hooks=$(nix eval --raw '.#darwinConfigurations.stibnite.config.home-manager.users.crs58.home.packages' \
    --apply 'ps: toString (map (p: p.drvPath) (builtins.filter (p: builtins.elem (p.pname or p.name or "") [ "notify-permission-prompt" "notify-permission-wait" ]) ps))')
  for d in $hooks; do
    out=$(nix build --print-out-paths --no-link "$d^out")
    echo "== $out"; rg -n 'curl|ntfy-send' "$out/bin/"
  done
} 2>&1 | tee "logs/cam87-evidence/4.5-green-$(/bin/date -u +%Y%m%dT%H%M%SZ).log"
```

The two hook derivations come from stibnite's evaluated home packages, so the scripts judged are the ones stibnite will run; the build of `aarch64-darwin` derivations runs on stibnite.
Expected: the scan passes with every mutant rejected; `hook-gate-dangerous-commands` passes; each hook script's only match is its `ntfy-send` call.
Commit: "hooks: post permission notices through ntfy-send".

- [ ] **Step 6: The notes (4.6)**

In `modules/lib/observability-notify-run.nix:21-23`, replace "on darwin it posts with /usr/bin/curl." with "on darwin, as on NixOS, it posts with the store curl and verifies ntfy.zt against caddy's root."; in `modules/clan/services/otel-collector/README.md:317`, replace the sentence on `/usr/bin/curl -sfk` with one stating that `ntfy-send` posts with the store curl on both platforms and verifies `ntfy.zt` against caddy's root.
Then:

```bash
rg -n -- '/usr/bin/curl|-sfk' modules pkgs
```

Expected: matches only inside `modules/checks/ntfy-tls-verification.nix`'s mutant lines.

- [ ] **Step 7: Pull request 2 (4.7)**

Run `nix fmt 2>&1 | tee logs/cam87-evidence/4.7-fmt-<ts>.log` and `nix fmt -- --fail-on-change`; record each changed check's cost after the change; open pull request 2, titled "Verify ntfy.zt's certificate in every ntfy client", whose description states in words what the TLS test, the token test and the scan establish, and which hosts' closures change.
Expected: nixbot green on `package-ntfy-send-test-tls-verification`, `package-ntfy-send-test-token-transport`, `ntfy-tls-verification`, `hook-gate-dangerous-commands`, `fleet-alert`, `otel-collector-config`, `otel-collector-darwin` and `nixos-magnetite`; `darwin-stibnite` evaluates, with its best-effort build recorded; the pull request merges through the queue.
