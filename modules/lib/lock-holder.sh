# shellcheck shell=bash
# describe_holder OWNER_FILE prints the holder of an exclusive flock on
# OWNER_FILE as "<user> pid <pid> since <ISO time> (<argv>)", read from
# /proc/locks, or fails when none is visible from this PID namespace. flock(1)
# records its own pid there, so the lock wrappers take OWNER_FILE with
# `flock --no-fork`, which execs their command in the locking process.
describe_holder() {
  [ -r /proc/locks ] || return 1
  local owner_file=$1
  local dev ino key pid
  read -r dev ino < <(stat -L -c '%d %i' "$owner_file")
  # /proc/locks prints the superblock device as major:minor in hex, using the
  # kernel's dev_t split (glibc gnu_dev_major/gnu_dev_minor).
  key=$(printf '%02x:%02x:%s' \
    $(((dev >> 8) & 0xfff)) $(((dev & 0xff) | ((dev >> 12) & 0xfff00))) "$ino")
  local type mode lock_pid lock_key
  pid=
  # Waiters are listed as "N: -> FLOCK ...", which shifts "->" into the type
  # field, so only granted locks match.
  while read -r _ type _ mode lock_pid lock_key _; do
    if [ "$type" = FLOCK ] && [ "$mode" = WRITE ] && [ "$lock_key" = "$key" ]; then
      pid=$lock_pid
      break
    fi
  done </proc/locks
  [ -n "$pid" ] && [ "$pid" != 0 ] && [ -d "/proc/$pid" ] || return 1
  local user started argv argv0
  user=$(stat -c %U "/proc/$pid") || return 1
  started=$(LC_ALL=C ps -o lstart= -p "$pid") || return 1
  started=$(date -d "$started" --iso-8601=seconds) || return 1
  argv=$(tr '\0' ' ' <"/proc/$pid/cmdline") || return 1
  argv=${argv% }
  argv0=${argv%% *}
  argv=${argv0##*/}${argv#"$argv0"}
  if [ "${#argv}" -gt 120 ]; then
    argv="${argv:0:117}..."
  fi
  printf '%s pid %s since %s (%s)' "$user" "$pid" "$started" "$argv"
}
