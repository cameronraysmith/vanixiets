# checks.x86_64-linux.fleet-deploy-watch: the rollback watcher
# (pkgs/by-name/fleet-deploy-watch) run as built against a fixture root
# (FLEET_DEPLOY_WATCH_ROOT), once as on NixOS and once as the darwin job
# (`--run`, FLEET_DEPLOY_WATCH_OS=Darwin, a recording launchctl). Polling is
# every 5 s, so "promptly" means within 7 s.
#
# - same closure, confirmed (F90): the system never changes and the deployer
#   confirms; the watcher ends promptly without rolling back, and on darwin
#   unloads its job;
# - changed, confirmed: ends promptly without rolling back;
# - changed, unconfirmed: returns to the recorded system once the window ends;
# - unchanged, unconfirmed: ends after activation-wait without rolling back.
#
# The watcher on a real host is observed by vmTests.x86_64-linux.fleet-deployer
# (NixOS) and task 5.4 of delegate-fleet-deploys (darwin).
{ lib, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      system,
      ...
    }:
    let
      launchctl = pkgs.writeShellScriptBin "launchctl" ''echo "$*" >>"$FLEET_DEPLOY_WATCH_ROOT/launchctl"'';
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.fleet-deploy-watch =
        pkgs.runCommand "fleet-deploy-watch"
          {
            nativeBuildInputs = [
              self'.packages.fleet-deploy-watch
              launchctl
            ];
          }
          ''
            failed=0
            fail() { echo "fleet-deploy-watch: $os $1: $2"; failed=1; }

            # setup <os>: a fresh fixture root running the system `old`.
            setup() {
              os=$1
              export FLEET_DEPLOY_WATCH_ROOT=$TMPDIR/root-$RANDOM
              r=$FLEET_DEPLOY_WATCH_ROOT
              mkdir -p "$r/run" "$r/var/run/fleet-deploy" "$r/run/fleet-deploy" "$r/etc/fleet-deploy-watch" \
                "$r/sys/old/bin" "$r/sys/new" "$r/nix/var/nix/profiles"
              for s in "$r/sys/old/activate" "$r/sys/old/bin/switch-to-configuration"; do
                printf '#!${pkgs.runtimeShell}\necho rolled-back >>"%s/rollbacks"\nln -sfn "%s/sys/old" "%s/run/current-system"\n' "$r" "$r" "$r" >"$s"
                chmod +x "$s"
              done
              ln -s "$r/sys/old" "$r/run/current-system"
              echo system >"$r/etc/fleet-deploy-watch/domain"
              echo org.vanixiets.fleet-deploy-watch >"$r/etc/fleet-deploy-watch/label"
              if [ "$os" = Darwin ]; then confirm=$r/var/run/fleet-deploy; else confirm=$r/run/fleet-deploy; fi
            }

            # start <id> <activation-wait> <confirm-window>
            start() {
              if [ "$os" = Darwin ]; then
                echo "$2 $3" | sed "s/^/$1 /" >"$r/var/run/fleet-deploy/request"
                FLEET_DEPLOY_WATCH_OS=Darwin fleet-deploy-watch --run >"$r/log" 2>&1 &
              else
                FLEET_DEPLOY_WATCH_OS=Linux fleet-deploy-watch "$1" "$2" "$3" >"$r/log" 2>&1 &
              fi
              pid=$!
              sleep 1
            }

            # ended <case> <seconds>: the watcher exits within <seconds>.
            ended() {
              for _ in $(seq "$2"); do
                kill -0 "$pid" 2>/dev/null || { wait "$pid"; return 0; }
                sleep 1
              done
              fail "$1" "still running after $2 s: $(tr '\n' ';' <"$r/log")"
              kill "$pid"
              return 1
            }

            rolledBack() { [ -e "$r/rollbacks" ]; }
            unloaded() { [ "$os" != Darwin ] || grep -qx 'bootout system/org.vanixiets.fleet-deploy-watch' "$r/launchctl" 2>/dev/null; }

            for os in Linux Darwin; do
              setup "$os"
              start same 7200 300
              touch "$confirm/same.confirmed"
              if ended "same closure, confirmed" 7; then
                rolledBack && fail "same closure, confirmed" "rolled back"
                unloaded || fail "same closure, confirmed" "job not unloaded"
              fi

              setup "$os"
              start changed 7200 300
              ln -sfn "$r/sys/new" "$r/run/current-system"
              sleep 6
              touch "$confirm/changed.confirmed"
              if ended "changed, confirmed" 7; then
                rolledBack && fail "changed, confirmed" "rolled back"
                unloaded || fail "changed, confirmed" "job not unloaded"
              fi

              setup "$os"
              start unconfirmed 7200 5
              ln -sfn "$r/sys/new" "$r/run/current-system"
              if ended "changed, unconfirmed" 20; then
                rolledBack || fail "changed, unconfirmed" "did not roll back: $(tr '\n' ';' <"$r/log")"
                [ "$(readlink "$r/run/current-system")" = "$r/sys/old" ] || fail "changed, unconfirmed" "not back on the recorded system"
              fi

              setup "$os"
              start idle 5 300
              if ended "unchanged, unconfirmed" 12; then
                rolledBack && fail "unchanged, unconfirmed" "rolled back"
                unloaded || fail "unchanged, unconfirmed" "job not unloaded"
              fi
            done
            [ "$failed" = 0 ]
            touch $out
          '';
    };
}
