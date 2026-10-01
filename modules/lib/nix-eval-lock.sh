# shellcheck shell=bash
# Body of the host-evaluation-lock wrapper around nix-eval-jobs. The Nix side
# (modules/lib/nix-eval-lock.nix) prepends `lock_file` and `evaluator`.
#
# One evaluation runs per host at a time. The wrapper takes an exclusive
# flock(2) on lock_file, waits (reporting the holder every 30 s) while another
# evaluation holds it, raises its own oom_score_adj to 900, and execs the real
# evaluator with the lock descriptor still open, so the lock lives exactly as
# long as the evaluator and any worker it forks, and the kernel drops it when
# they exit, however they exit.
#
# Two inodes, because flock(1) takes the lock in its own process: /proc/locks
# records that process's pid, and once a short-lived flock(1) exits the kernel
# hides the entry (fs/locks.c locks_show skips owners whose pid is gone). The
# queue lock (lock_file) is therefore taken through a descriptor this shell
# keeps, so waiting can be reported every 30 s, and the owner lock
# (lock_file.owner) is taken by `flock --no-fork`, which execs the evaluator in
# the process that locked it. Only a holder of the queue lock ever takes the
# owner lock, so it never waits, and its /proc/locks entry carries the live
# evaluator's pid.
#
# Both locks are taken on read-only descriptors. flock(2) needs no write
# access, and nixbot runs its evaluator in a bubblewrap sandbox that sees the
# lock files only through a read-only bind mount; a flock is on the inode, so
# it is shared across mount and PID namespaces.
#
# Holder details come from /proc/locks rather than from anything the holder
# writes: a sandboxed holder cannot write outside its sandbox, and kernel
# state cannot go stale. From inside a PID namespace the holder may not be
# visible; the waiting line then says so instead of naming it.

owner_file=$lock_file.owner
report_interval=30
conflict=75

for file in "$lock_file" "$owner_file"; do
  if [ ! -r "$file" ]; then
    echo "nix-eval-jobs: the host evaluation lock $file is missing or unreadable; refusing to run an unserialised evaluation" >&2
    exit 1
  fi
done
exec {lock_fd}<"$lock_file"

# Prints the owner-lock holder as "<user> pid <pid> since <ISO time> (<argv>)",
# or fails when no holder is visible from this PID namespace (or this host has
# no /proc/locks).
describe_holder() {
  [ -r /proc/locks ] || return 1
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

status=0
flock -n -E "$conflict" "$lock_fd" || status=$?
while [ "$status" -ne 0 ]; do
  [ "$status" -eq "$conflict" ] || exit "$status"
  if holder=$(describe_holder); then
    echo "nix-eval-jobs: waiting for the host evaluation lock held by $holder; evaluations on this host run one at a time to avoid exhausting memory" >&2
  else
    echo "nix-eval-jobs: waiting for the host evaluation lock held by another evaluation on this host (its process is not visible from here); evaluations on this host run one at a time to avoid exhausting memory" >&2
  fi
  status=0
  flock -w "$report_interval" -E "$conflict" "$lock_fd" || status=$?
done

# The evaluator is the cheapest victim when the host runs out of memory:
# nix-eval-jobs >= 2.35.3 requeues an OOM-killed worker and retries it alone,
# while the alternatives the kernel otherwise picks (nix-daemon connection
# workers, the CI daemon, the desktop) are not retried. Raising the value
# needs no privilege. Hosts without the interface (darwin) skip it.
if [ -e /proc/self/oom_score_adj ]; then
  echo 900 >/proc/self/oom_score_adj
fi

exec flock --no-fork "$owner_file" "$evaluator" "$@"
