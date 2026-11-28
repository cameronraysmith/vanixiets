# shellcheck shell=bash
# Body of nix-build-locked; modules/lib/nix-build-lock.nix prepends its
# settings and lock-holder.sh, and modules/README.md §Evaluators states the
# rules it enforces. Pressure is read again once the lock is held and the lock
# released if it has risen, so a build waiting on pressure never holds the
# queue. The locks are taken as in nix-eval-lock.sh, on read-only descriptors
# kept open across the exec, so they last exactly as long as the build.

owner_file=$lock_file.owner
conflict=75
deadline=$((SECONDS + max_wait))

usage() {
  echo "usage: nix-build-locked COMMAND [ARGUMENT...]"
  echo "Runs COMMAND as this host's one build at a time, under an exclusive flock on"
  echo "$lock_file, once some avg60 in $pressure_file is below $pressure_threshold."
  echo "Waits at most ${max_wait}s, then exits 75 without running COMMAND; otherwise"
  echo "exits with COMMAND's status."
}

case "${1-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "")
    usage >&2
    exit 2
    ;;
  -*)
    echo "nix-build-locked: unknown option $1; the build command comes first" >&2
    usage >&2
    exit 2
    ;;
esac

for file in "$lock_file" "$owner_file"; do
  if [ ! -r "$file" ]; then
    echo "nix-build-locked: the host build lock $file is missing or unreadable; refusing to run an unserialised build" >&2
    exit 1
  fi
done
exec {lock_fd}<"$lock_file"

give_up() {
  echo "nix-build-locked: gave up after ${max_wait}s waiting $1; the build did not run" >&2
  exit "$conflict"
}

# Sets `seconds` to what is left before max_wait, at most report_interval;
# gives up at zero.
next_wait() {
  seconds=$((deadline - SECONDS))
  [ "$seconds" -gt 0 ] || give_up "$1"
  [ "$seconds" -le "$report_interval" ] || seconds=$report_interval
}

# Sets `pressure` to some avg60 from pressure_file and succeeds when it is
# below pressure_threshold. The threshold is an integer, so comparing the
# integer part of the reading is exact.
pressure_ok() {
  local kind field
  pressure=
  if [ -r "$pressure_file" ]; then
    while read -r kind _ field _; do
      if [ "$kind" = some ]; then
        pressure=${field#avg60=}
        break
      fi
    done <"$pressure_file"
  fi
  if [[ ! $pressure =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "nix-build-locked: cannot read some avg60 from $pressure_file; refusing to build without knowing the host's memory pressure" >&2
    exit 1
  fi
  [ "${pressure%%.*}" -lt "$pressure_threshold" ]
}

wait_for_pressure() {
  until pressure_ok; do
    next_wait "for memory pressure to fall below $pressure_threshold"
    echo "nix-build-locked: waiting for memory pressure to fall: some avg60 in $pressure_file is $pressure, at or above $pressure_threshold; a build started now risks exhausting the host's memory" >&2
    sleep "$seconds"
  done
}

take_lock() {
  local status=0
  flock -n -E "$conflict" "$lock_fd" || status=$?
  while [ "$status" -ne 0 ]; do
    [ "$status" -eq "$conflict" ] || exit "$status"
    next_wait "for the host build lock"
    if holder=$(describe_holder "$owner_file"); then
      echo "nix-build-locked: waiting for the host build lock held by $holder; builds on this host run one at a time to avoid exhausting memory" >&2
    else
      echo "nix-build-locked: waiting for the host build lock held by another build on this host (its process is not visible from here); builds on this host run one at a time to avoid exhausting memory" >&2
    fi
    status=0
    flock -w "$seconds" -E "$conflict" "$lock_fd" || status=$?
  done
}

while :; do
  wait_for_pressure
  take_lock
  pressure_ok && break
  flock -u "$lock_fd"
done

exec flock --no-fork "$owner_file" "$@"
