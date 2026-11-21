# fleet-deploy-watch <id> <activation-wait> <confirm-window>     (NixOS)
# fleet-deploy-watch --arm <id> <activation-wait> <confirm-window> (darwin, root)
# fleet-deploy-watch --run                                       (darwin, the job)
# fleet-deploy-watch --disarm                                    (darwin, root)
#
# Started on a target by the fleet deployer before it deploys (design D10),
# so it outlives the SSH connection and the activation: on NixOS through
# systemd-run, on darwin as the launchd job its configuration declares
# (/etc/fleet-deploy-watch, modules/system/fleet-deploy-target.nix), which
# `--arm` bootstraps into launchd's system domain, so it runs as root
# whichever user's session armed it (F84). One job per host: `--arm` fails
# while the job is loaded rather than replace it.
#
# The watcher records the running system, waits up to <activation-wait>
# seconds for /run/current-system to change, then up to <confirm-window>
# seconds for <dir>/<id>.confirmed, which the deployer writes as soon as it
# reaches the host again. Without it, the host returns to the recorded
# system: a new profile generation pointing at it, then its activation, which
# also writes a deploy record. A system that never changes ends the watcher
# without action. The confirmation ends it whenever it arrives, during the
# activation wait too, so a deploy of the running closure does not leave
# the watcher loaded for <activation-wait> seconds (F90).
#
# No `set -e`: the watcher unloads its own job on every path (finish) and
# never exits early on error.
#
# FLEET_DEPLOY_WATCH_ROOT (prefixed to every path the watcher reads or
# writes) and FLEET_DEPLOY_WATCH_OS (in place of `uname -s`) exist for
# checks.x86_64-linux.fleet-deploy-watch only. sudo, launchd and systemd-run
# start the watcher with neither set.
set -u

root=${FLEET_DEPLOY_WATCH_ROOT:-}
job=$root/etc/fleet-deploy-watch
domain='' label=''

if [ "${FLEET_DEPLOY_WATCH_OS:-$(uname -s)}" = Darwin ]; then
  dir=$root/var/run/fleet-deploy
  domain=$(cat "$job/domain")
  label=$(cat "$job/label")
else
  dir=$root/run/fleet-deploy
fi

case "${1:-}" in
  --arm)
    [ "$#" = 4 ] || {
      echo "usage: fleet-deploy-watch --arm <id> <activation-wait> <confirm-window>" >&2
      exit 2
    }
    [ "$(id -u)" = 0 ] || {
      echo "fleet-deploy-watch: --arm must run as root" >&2
      exit 1
    }
    if launchctl print "$domain/$label" >/dev/null 2>&1; then
      echo "fleet-deploy-watch: $label is already loaded in $domain (request $(cat "$dir/request" 2>/dev/null || echo unknown)); a deploy is in progress or its watcher did not finish" >&2
      exit 1
    fi
    install -d -m 0755 -o root -g wheel "$dir"
    printf '%s %s %s\n' "$2" "$3" "$4" >"$dir/request"
    # launchd loads a plist only from a regular file owned by root and
    # writable by nobody else, not the /etc/static symlink.
    install -m 0644 -o root -g wheel "$job/job.plist" "$dir/job.plist"
    exec launchctl bootstrap "$domain" "$dir/job.plist"
    ;;
  --disarm)
    rm -f "$dir/request" "$dir/job.plist" "$dir"/*.confirmed
    launchctl bootout "$domain/$label"
    exit 0
    ;;
  --run)
    read -r id wait window <"$dir/request"
    ;;
  *)
    id=$1 wait=$2 window=$3
    ;;
esac

mkdir -p "$dir"
chmod 0755 "$dir"

finish() {
  rm -f "$dir/$id.confirmed"
  if [ -n "$domain" ]; then
    rm -f "$dir/request" "$dir/job.plist"
    # Unloads this job, ending this process: the last step.
    launchctl bootout "$domain/$label"
  fi
  exit 0
}

current() { readlink -f "$root/run/current-system"; }

before=$(current)
echo "fleet-deploy-watch $id: watching $before as $(id -un)"
waited=0
while [ "$(current)" = "$before" ]; do
  # A deploy of the running closure never changes the link; its confirmation
  # ends the watcher as soon as it arrives (F90).
  if [ -e "$dir/$id.confirmed" ]; then
    echo "fleet-deploy-watch $id: confirmed; the system did not change"
    finish
  fi
  if [ "$waited" -ge "$wait" ]; then
    echo "fleet-deploy-watch $id: the system did not change within ${wait}s"
    finish
  fi
  sleep 5
  waited=$((waited + 5))
done

echo "fleet-deploy-watch $id: activated $(current); waiting ${window}s for confirmation"
waited=0
while [ ! -e "$dir/$id.confirmed" ]; do
  if [ "$waited" -ge "$window" ]; then
    echo "fleet-deploy-watch $id: no confirmation; returning to $before"
    nix-env -p "$root/nix/var/nix/profiles/system" --set "$before"
    if [ -n "$domain" ]; then
      "$before/activate"
    else
      "$before/bin/switch-to-configuration" switch
    fi
    finish
  fi
  sleep 5
  waited=$((waited + 5))
done
echo "fleet-deploy-watch $id: confirmed"
finish
