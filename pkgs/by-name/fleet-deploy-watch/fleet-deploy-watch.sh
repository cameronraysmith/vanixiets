# fleet-deploy-watch <id> <activation-wait> <confirm-window>
# fleet-deploy-watch --stop-stale        (darwin: remove leftover watchers)
#
# Started on a target by the fleet deployer before it deploys (design D10):
# systemd-run on NixOS, launchctl submit on darwin, so it outlives the SSH
# connection and the activation. It records the running system, waits up to
# <activation-wait> seconds for /run/current-system to change, then up to
# <confirm-window> seconds for <dir>/<id>.confirmed, which the deployer
# writes as soon as it reaches the host again. Without it, the host returns
# to the recorded system: a new profile generation pointing at it, then its
# activation, which also writes a deploy record. A system that never changes
# ends the watcher without action.
#
# No `set -e`: launchd restarts a submitted job that exits, so the watcher
# removes its own job on every path (finish) and never exits early on error.
set -u

darwin=false
[ "$(uname -s)" = Darwin ] && darwin=true

if [ "${1:-}" = --stop-stale ]; then
  if $darwin; then
    launchctl list | awk '$3 ~ /^org\.vanixiets\.fleet-deploy-watch\./ { print $3 }' |
      while read -r label; do launchctl remove "$label"; done
  fi
  exit 0
fi

id=$1 wait=$2 window=$3
if $darwin; then
  dir=/var/run/fleet-deploy
else
  dir=/run/fleet-deploy
fi
mkdir -p "$dir"
chmod 0755 "$dir"

finish() {
  rm -f "$dir/$id.confirmed"
  if $darwin; then
    launchctl remove "org.vanixiets.fleet-deploy-watch.$id"
  fi
  exit 0
}

current() { readlink -f /run/current-system; }

before=$(current)
echo "fleet-deploy-watch $id: watching $before"
waited=0
while [ "$(current)" = "$before" ]; do
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
    nix-env -p /nix/var/nix/profiles/system --set "$before"
    if $darwin; then
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
