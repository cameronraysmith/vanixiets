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
            # Content-Length lets curl finish without reading to the TLS
            # stream's end, which the server closes without close_notify.
            reply = b'{"event":"message"}\n'
            self.send_response(200)
            self.send_header("Content-Length", str(len(reply)))
            self.end_headers()
            self.wfile.write(reply)
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
