# checks.x86_64-linux.langfuse-query: runs the langfuse-query script, built
# as the app builds it but with stub sops and langfuse executables that record
# each call, keyed on the packaged CLI's own contract, and with the key files
# the app itself carries.
#
# It fails when an allow-listed action is not a GET in the contract the CLI
# sends requests by, when any operation that is not a GET, or any alias of
# one, gets past the wrapper or reaches sops or the CLI, when a refused global
# option (--host, --secret-key, --api-version, ...) is passed through, when a
# convenience subcommand calls an action off the allow-list, when the key
# appears in an argument list or fails to reach the CLI through its
# environment, when an undecryptable key does not end the run with exactly
# one stderr line before any request, while help still works without it, and
# when the app's key files are not the Viewer key's clan secrets or are the
# collectors' shared var: the stub sops decrypts only the Viewer ciphertext.
#
# One system: the derivation runs shell scripts over JSON, and no input to it
# differs by platform.
{ lib, ... }:
{
  perSystem =
    {
      self',
      config,
      pkgs,
      system,
      ...
    }:
    let
      cli = config.packages.langfuse-cli;
      secretKey = "sk-lf-00000000-1111-2222-3333-444444444444"; # gitleaks:allow
      publicKey = "pk-lf-00000000-1111-2222-3333-444444444444"; # gitleaks:allow
      viewerPublic = ../../sops/secrets/langfuse-viewer-public-key/secret;
      viewerSecret = ../../sops/secrets/langfuse-viewer-secret-key/secret;

      # Each stub appends one JSON line per call to $STUB_LOG.
      stubSops = pkgs.writeShellScriptBin "sops" ''
        ${lib.getExe pkgs.jq} -cn --args '{tool: "sops", argv: $ARGS.positional}' -- "$@" >> "$STUB_LOG"
        [ ! -e "$STUB_DIR/sops-fails" ] || { echo "Failed to get the data key required to decrypt the SOPS file." >&2; exit 128; }
        file=''${*: -1}
        if ${pkgs.diffutils}/bin/cmp -s "$file" ${viewerPublic}; then
          printf '%s' ${publicKey}
        elif ${pkgs.diffutils}/bin/cmp -s "$file" ${viewerSecret}; then
          printf '%s' ${secretKey}
        else
          echo "stub sops: $file is not a Viewer key file" >&2
          exit 1
        fi
      '';
      stubLangfuse = pkgs.writeShellScriptBin "langfuse" ''
        ${lib.getExe pkgs.jq} -cn --args '{tool: "langfuse", argv: $ARGS.positional,
          secret: env.LANGFUSE_SECRET_KEY, public: env.LANGFUSE_PUBLIC_KEY,
          base: env.LANGFUSE_BASE_URL, host: env.LANGFUSE_HOST, apiVersion: env.LANGFUSE_API_VERSION}' -- "$@" >> "$STUB_LOG"
        printf '%s\n' '{"data":[{"id":"o1","traceId":"t1","parentObservationId":null,"type":"AGENT","name":"n","startTime":"2026-01-01T00:00:00Z","input":"i","output":"o","usageDetails":{"total":1},"totalCost":0.5}],"meta":{}}'
      '';

      app = pkgs.writeShellApplication {
        name = "langfuse-query";
        runtimeInputs = [
          stubLangfuse
          stubSops
          pkgs.jq
          pkgs.gawk
          pkgs.gnugrep
          pkgs.gnused
          pkgs.coreutils
        ];
        text = builtins.readFile ../apps/langfuse-query.sh;
      };
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        langfuse-query =
          pkgs.runCommand "langfuse-query"
            {
              nativeBuildInputs = [ pkgs.jq ];
              script = ../apps/langfuse-query.sh;
              contracts = "${cli}/lib/langfuse-cli/dist/contracts";
              passthru.meta.description = "langfuse-query passes only GET read actions to the Langfuse CLI, refuses the rest before any request and keeps the key out of argument lists";
            }
            ''
              export STUB_LOG=$TMPDIR/log STUB_DIR=$TMPDIR
              failed=0
              miss() { echo "FAIL: $*"; failed=1; }
              run() {
                : > "$STUB_LOG"
                code=0
                ${lib.getExe app} "$@" < /dev/null > "$TMPDIR/stdout" 2> "$TMPDIR/stderr" || code=$?
                ! jq -se 'any(.[]; .argv | tostring | contains("${secretKey}") or contains("${publicKey}"))' "$STUB_LOG" > /dev/null ||
                  miss "$*: the key appears in an argument list"
              }
              calls() { jq -s --arg t "$1" 'map(select(.tool == $t)) | length' "$STUB_LOG"; }

              contract=$contracts/$(jq -r .latest "$contracts/catalog.json").json
              echo "contract: $contract"
              mapfile -t allowed < <(sed -n '/^read_actions=(/,/^)/p' "$script" | grep -o '"[^"]*"' | tr -d '"')
              [ "''${#allowed[@]}" -gt 0 ] || miss "no allow-list found in the script"

              echo "--- the app decrypts the Viewer key's clan secrets, not the collectors' var"
              for kind in PUBLIC SECRET; do
                file=$(sed -n "s/^LANGFUSE_QUERY_''${kind}_KEY_FILE=//p" ${self'.apps.langfuse-query.program} | tr -d "'")
                [ -n "$file" ] || miss "the app sets no LANGFUSE_QUERY_''${kind}_KEY_FILE"
                export "LANGFUSE_QUERY_''${kind}_KEY_FILE=$file"
                for collectors in ${../../vars/shared/langfuse/public-key/secret} ${../../vars/shared/langfuse/secret-key/secret}; do
                  ! cmp -s "$file" "$collectors" || miss "the app's $kind key file is the collectors' shared var"
                done
              done
              cmp -s "$LANGFUSE_QUERY_PUBLIC_KEY_FILE" ${viewerPublic} || miss "the app's public key file is not langfuse-viewer-public-key"
              cmp -s "$LANGFUSE_QUERY_SECRET_KEY_FILE" ${viewerSecret} || miss "the app's secret key file is not langfuse-viewer-secret-key"

              echo "--- every allow-listed action is a GET in the contract and reaches the CLI with the key in its environment"
              for entry in "''${allowed[@]}"; do
                read -r resource action <<<"$entry"
                method=$(jq -r --arg r "$resource" --arg a "$action" \
                  '[.operations[] | select(.command.resource == $r and .command.action == $a) | .method] | if length == 1 then .[0] else "none" end' "$contract")
                [ "$method" = GET ] || miss "$entry is $method in the contract, not GET"
                run api "$resource" "$action" --json
                [ "$code" = 0 ] || miss "$entry: exit $code"
                jq -se --arg r "$resource" --arg a "$action" \
                  'map(select(.tool == "langfuse")) == [{tool: "langfuse", argv: ["api", $r, $a, "--json"],
                    secret: "${secretKey}", public: "${publicKey}", base: "https://cloud.langfuse.com", host: null, apiVersion: null}]' \
                  "$STUB_LOG" > /dev/null || miss "$entry: the CLI saw $(cat "$STUB_LOG")"
              done

              echo "--- no operation other than a GET, and no alias of one, gets past the wrapper"
              refused=0
              while IFS=$'\t' read -r resource action; do
                run api "$resource" "$action" --body-json '{}'
                if [ "$code" != 2 ] || [ "$(calls langfuse)" != 0 ] || [ "$(calls sops)" != 0 ]; then
                  miss "$resource $action: exit $code, $(calls langfuse) CLI and $(calls sops) sops calls"
                fi
                grep -q "^langfuse-query: refusing \"$resource $action\"" "$TMPDIR/stderr" || miss "$resource $action: no refusal message"
                refused=$((refused + 1))
              done < <(jq -r '.operations[] | select(.method != "GET")
                | ([.command] + (.command.aliases // []))[] | [.resource, .action] | @tsv' "$contract")
              [ "$refused" -gt 50 ] || miss "only $refused non-GET commands found in the contract"
              echo "refused $refused non-GET commands"

              echo "--- global options that change the host, key, contract or output are refused"
              for option in --host=https://example.invalid "--secret-key x" "--public-key x" "--api-version 3" "--env f" "--output f" --curl --show-secrets "--timeout 1"; do
                run api observations list $option
                [ "$code" = 2 ] && [ "$(calls langfuse)" = 0 ] || miss "$option: exit $code, $(calls langfuse) CLI calls"
              done

              echo "--- convenience subcommands call only allow-listed actions"
              for args in "traces --user u --from 1d" "trace t1" "session s1" "search needle"; do
                run $args
                [ "$code" = 0 ] || miss "$args: exit $code: $(cat "$TMPDIR/stderr")"
                while read -r pair; do
                  ok=false
                  for entry in "''${allowed[@]}"; do [ "$entry" != "$pair" ] || ok=true; done
                  [ "$ok" = true ] || miss "$args called $pair"
                done < <(jq -r 'select(.tool == "langfuse") | .argv[1:3] | join(" ")' "$STUB_LOG")
              done

              echo "--- an undecryptable key ends the run with one line and no request"
              touch "$STUB_DIR/sops-fails"
              run traces
              [ "$code" = 1 ] && [ "$(calls langfuse)" = 0 ] || miss "no key: exit $code, $(calls langfuse) CLI calls"
              [ "$(wc -l < "$TMPDIR/stderr")" = 1 ] && grep -q '^langfuse-query: cannot decrypt the Langfuse Viewer key' "$TMPDIR/stderr" ||
                miss "no key: stderr is $(cat "$TMPDIR/stderr")"
              run api help observations list
              [ "$code" = 0 ] && [ "$(calls langfuse)" = 1 ] && [ "$(calls sops)" = 0 ] || miss "help without a key: exit $code"
              rm "$STUB_DIR/sops-fails"

              [ "$failed" = 0 ] || exit 1
              touch "$out"
            '';
      };
    };
}
