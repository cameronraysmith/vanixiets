# checks.x86_64-linux.obs-query: runs the obs-query app against a stub ssh,
# which executes the remote command locally, and a stub store on
# 127.0.0.1:4000, with stub sudo and a recording curl on the remote PATH.
#
# It fails when a query reaches the store as anything other than its exact
# text (the store's form decoding is the oracle, so quoting or encoding damage
# shows as a different decoded value), when the remote command line is not
# the constant `bash -s`, when an error answer exits 0, whether the HTTP
# status or only the body reports it, when the password appears in the
# argument list of ssh, sudo or curl, while it must still reach the store as
# Basic credentials, so the scan cannot pass on a request that sent none, and
# when an unreadable password file does not end the run with exactly one
# stderr line naming its path, which is how a drifted path shows.
#
# One system: the derivation runs a shell script and a Python stub, and no
# input to it differs by platform.
{ lib, ... }:
{
  perSystem =
    {
      self',
      pkgs,
      system,
      ...
    }:
    let
      password = "0f1e2d3c4b5a69788796a5b4c3d2e1f0";
      passwordPath = "/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password";

      # Every character class a shell or a form encoding could damage: spaces,
      # `+`, `&`, `=`, `%`, both quotes, command substitution, backticks, `;`,
      # a newline, a tab and non-ASCII text.
      awkwardPromql = "sum by (host_name) (rate(x{a=\"b&c=d\", e='$(touch pwned)'}[5m])) + 1 % 2 ; `touch pwned`\n\t# é";
      awkwardSql = "SELECT 'a+b & c=d %41 \"q\" $(touch pwned) `touch pwned`; ''x''' AS \"s\"\nFROM \"ci_build\"";

      vector = {
        status = "success";
        data = {
          resultType = "vector";
          result = [
            {
              metric.host_name = "magnetite";
              value = [
                1794000000.5
                "7"
              ];
            }
          ];
        };
      };
      matrix = {
        status = "success";
        data = {
          resultType = "matrix";
          result = [
            {
              metric.host_name = "pyrite";
              values = [
                [
                  1794000000
                  "1"
                ]
                [
                  1794000060
                  "2"
                ]
              ];
            }
          ];
        };
      };
      records = {
        output = [
          {
            records = {
              schema.column_schemas = [
                {
                  name = "s";
                  data_type = "String";
                }
                {
                  name = "n";
                  data_type = "Int64";
                }
              ];
              rows = [
                [
                  "x"
                  null
                ]
              ];
              total_rows = 1;
            };
          }
        ];
        execution_time_ms = 1;
      };

      # args: the app's arguments; reply: the stub's status and body; form:
      # the decoded form the store must receive; tableLines: lines --table
      # output must contain, when the case runs with --table.
      cases = [
        {
          name = "an instant PromQL query reaches the store as its exact text and its answer is printed";
          args = [
            "promql"
            "--"
            awkwardPromql
          ];
          path = "/v1/prometheus/api/v1/query";
          db = "fleet";
          status = 200;
          body = builtins.toJSON vector;
          form.query = [ awkwardPromql ];
          exit = 0;
        }
        {
          name = "a range PromQL query sends start, end and step";
          args = [
            "--table"
            "promql"
            "up"
            "--start"
            "2026-11-07T00:00:00Z"
            "--end"
            "1794000060"
            "--step"
            "1m"
          ];
          path = "/v1/prometheus/api/v1/query_range";
          db = "fleet";
          status = 200;
          body = builtins.toJSON matrix;
          form = {
            query = [ "up" ];
            start = [ "2026-11-07T00:00:00Z" ];
            end = [ "1794000060" ];
            step = [ "1m" ];
          };
          exit = 0;
          tableLines = [
            "host_name=pyrite  1794000060  2"
          ];
        }
        {
          name = "an SQL statement reaches the named database as its exact text";
          args = [
            "sql"
            "devloop"
            awkwardSql
            "--table"
          ];
          path = "/v1/sql";
          db = "devloop";
          status = 200;
          body = builtins.toJSON records;
          form.sql = [ awkwardSql ];
          exit = 0;
          tableLines = [
            "s  n"
            "x  NULL"
          ];
        }
        {
          name = "a TQL statement is sent with its keyword";
          args = [
            "tql"
            "fleet"
            "EVAL (0, 10, '5s') up"
          ];
          path = "/v1/sql";
          db = "fleet";
          status = 200;
          body = builtins.toJSON records;
          form.sql = [ "TQL EVAL (0, 10, '5s') up" ];
          exit = 0;
        }
        {
          name = "an SQL error answered with HTTP 200 exits 1";
          args = [
            "sql"
            "fleet"
            "SELECT 1"
          ];
          path = "/v1/sql";
          db = "fleet";
          status = 200;
          body = builtins.toJSON {
            code = 4001;
            error = "Table not found";
            execution_time_ms = 0;
          };
          form.sql = [ "SELECT 1" ];
          exit = 1;
        }
        {
          name = "a PromQL error answered with HTTP 200 and an empty result exits 1";
          args = [
            "promql"
            "up"
          ];
          path = "/v1/prometheus/api/v1/query";
          db = "fleet";
          status = 200;
          body = builtins.toJSON {
            status = "error";
            errorType = "bad_data";
            error = "unclosed left parenthesis";
            data = {
              resultType = "vector";
              result = [ ];
            };
          };
          form.query = [ "up" ];
          exit = 1;
        }
        {
          name = "an error status exits 1";
          args = [
            "sql"
            "fleet"
            "SELECT 1"
          ];
          path = "/v1/sql";
          db = "fleet";
          status = 400;
          body = builtins.toJSON {
            code = 1004;
            error = "Failed to plan SQL";
            execution_time_ms = 0;
          };
          form.sql = [ "SELECT 1" ];
          exit = 1;
        }
        {
          name = "a body that is not JSON exits 1";
          args = [
            "sql"
            "fleet"
            "SELECT 1"
          ];
          path = "/v1/sql";
          db = "fleet";
          status = 200;
          body = "Internal Server Error";
          form.sql = [ "SELECT 1" ];
          exit = 1;
        }
        {
          name = "an unreadable password exits 1 with one line naming its path and sends nothing";
          args = [
            "sql"
            "fleet"
            "SELECT 1"
          ];
          sudoFails = true;
          status = 200;
          body = builtins.toJSON records;
          stderr = "obs-query: cannot read the regulator password at ${passwordPath} on magnetite";
          exit = 1;
        }
      ];

      store = pkgs.writeText "obs-query-store-stub.py" ''
        import base64, json, sys
        from http.server import BaseHTTPRequestHandler, HTTPServer
        from urllib.parse import parse_qs, urlsplit

        reply_dir, log_path, ready_path = sys.argv[1:4]

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                credentials = None
                auth = self.headers.get("Authorization", "")
                if auth.startswith("Basic "):
                    credentials = base64.b64decode(auth[6:]).decode()
                try:
                    form = parse_qs(raw.decode("ascii"), keep_blank_values=True, strict_parsing=True)
                except (UnicodeDecodeError, ValueError) as error:
                    form = {"unparseable": [repr(error)]}
                with open(log_path, "a") as log:
                    log.write(json.dumps({
                        "path": urlsplit(self.path).path,
                        "db": self.headers.get("x-greptime-db-name"),
                        "credentials": credentials,
                        "form": form,
                    }) + "\n")
                status = int(open(f"{reply_dir}/status").read())
                data = open(f"{reply_dir}/body", "rb").read()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *args):
                pass

        server = HTTPServer(("127.0.0.1", 4000), Handler)
        open(ready_path, "w").close()
        server.serve_forever()
      '';

      runCase =
        case:
        let
          sudoFails = case.sudoFails or false;
          expected = builtins.toJSON {
            inherit (case) path db form;
            credentials = "regulator:${password}";
          };
        in
        ''
          echo ${lib.escapeShellArg "--- ${case.name}"}
          printf '%s' ${toString case.status} > "$reply/status"
          printf '%s' ${lib.escapeShellArg case.body} > "$reply/body"
          ${if sudoFails then ''touch "$reply/sudo-fails"'' else ''rm -f "$reply/sudo-fails"''}
          : > "$requests"
          code=0
          (cd "$work" && ${self'.apps.obs-query.program} ${lib.escapeShellArgs case.args}) > "$work/stdout" 2> "$work/stderr" || code=$?
          cat "$work/stdout" "$work/stderr"
          [ "$code" = ${toString case.exit} ] || miss "exit status $code, expected ${toString case.exit}"
          ${
            if sudoFails then
              ''
                [ ! -s "$requests" ] || miss "the store received $(cat "$requests"), expected nothing"
              ''
            else
              ''
                [ "$(wc -l < "$requests")" = 1 ] || miss "the store received $(wc -l < "$requests") requests, expected 1"
                jq -e --argjson expected ${lib.escapeShellArg expected} '. == $expected' "$requests" > /dev/null ||
                  miss "the store received $(cat "$requests"), expected "${lib.escapeShellArg expected}
              ''
          }
          ${lib.optionalString (case ? stderr) ''
            [ "$(cat "$work/stderr")" = ${lib.escapeShellArg case.stderr} ] ||
              miss "stderr is not exactly: "${lib.escapeShellArg case.stderr}
          ''}
          ${lib.optionalString (case.exit == 0 && !(builtins.elem "--table" case.args)) ''
            jq -e --argjson body ${lib.escapeShellArg case.body} '. == $body' "$work/stdout" > /dev/null ||
              miss "the printed JSON differs from the store's answer"
          ''}
          ${lib.concatMapStrings (line: ''
            grep -qxF -- ${lib.escapeShellArg line} "$work/stdout" || miss ${lib.escapeShellArg "the table lacks the line: ${line}"}
          '') (case.tableLines or [ ])}
          [ ! -e "$work/pwned" ] || miss "query text was executed as a command"
        '';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        obs-query =
          pkgs.runCommand "obs-query"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.curl
                pkgs.jq
              ];
              passthru.meta.description = "obs-query sends exact query text over a constant remote command, keeps the password out of argument lists and exits non-zero on store errors";
            }
            ''
              work=$TMPDIR/work reply=$TMPDIR/reply requests=$TMPDIR/requests argv=$TMPDIR/argv
              mkdir -p "$work" "$reply" "$TMPDIR/bin"
              : > "$argv"
              failed=0
              miss() { echo "FAIL: $*"; failed=1; }

              # Each stub appends its name and arguments, one per line, to $argv.
              cat > "$TMPDIR/bin/ssh" <<EOF
              #!${pkgs.runtimeShell}
              printf '%s\n' ssh "\$@" >> "$argv"
              [ "\$*" = "-T magnetite.zt bash -s" ] || { echo "stub ssh: unexpected arguments: \$*" >&2; exit 255; }
              exec ${pkgs.runtimeShell} -s
              EOF
              cat > "$TMPDIR/bin/sudo" <<EOF
              #!${pkgs.runtimeShell}
              printf '%s\n' sudo "\$@" >> "$argv"
              [ "\$*" = "-n cat ${passwordPath}" ] || { echo "stub sudo: unexpected arguments: \$*" >&2; exit 1; }
              [ ! -e "$reply/sudo-fails" ] || { echo "sudo: a password is required" >&2; exit 1; }
              printf '%s\n' ${password}
              EOF
              cat > "$TMPDIR/bin/curl" <<EOF
              #!${pkgs.runtimeShell}
              printf '%s\n' curl "\$@" >> "$argv"
              exec ${lib.getExe pkgs.curl} "\$@"
              EOF
              chmod +x "$TMPDIR/bin/"*
              export PATH=$TMPDIR/bin:$PATH

              python3 ${store} "$reply" "$requests" "$TMPDIR/ready" &
              store_pid=$!
              for _ in $(seq 100); do [ -e "$TMPDIR/ready" ] && break; sleep 0.1; done
              [ -e "$TMPDIR/ready" ] || { echo "the store stub did not start"; exit 1; }

              ${lib.concatMapStrings runCase cases}

              echo "--- the password appears in no argument list"
              grep -qx ssh "$argv" && grep -qx sudo "$argv" && grep -qx curl "$argv" ||
                miss "a stub was never invoked: $(sort -u "$argv" | grep -x -e ssh -e sudo -e curl | tr '\n' ' ')"
              if grep -nF ${password} "$argv"; then
                miss "the password appears in an argument list"
              fi

              kill "$store_pid"
              [ "$failed" = 0 ] || exit 1
              cp "$argv" "$out"
            '';
      };
    };
}
