#!/usr/bin/env bash
# tm-restore — resumably restore a path from the archival Time Machine source
# drive to its equivalent location on this disk (or, with --to, to a chosen
# destination).
#
# Data-root resolution (first hit wins):
#   --from <root>       explicit, per invocation
#   $TM_DATA_ROOT       environment override
#   $TM_DATA_ROOT_FILE  sops-decrypted default (path injected at build time)
#
# rsync policy: archive + resumable + additive. --update (never clobber a newer
# live file) and no --delete by default. The source is an immutable Time Machine
# snapshot, so --append-verify resume is always safe.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tm-restore [options] <live-abs-path>...

Restore one or more absolute paths from the archival Time Machine source drive
to their equivalent locations on this disk. Directories sync recursively with
trailing-slash-correct rsync constructed for you. Successful directory restores
are registered with the zoxide directory index.

Options:
  -n, --dry-run    Preview only (rsync -n -i); write nothing.
      --to DEST    Restore a single source path to DEST (its exact destination)
                   instead of its equivalent location. Requires exactly one
                   <live-abs-path>. DEST becomes a copy of the source; it is not
                   a parent to nest under.
      --mirror     Add --delete: make the destination an exact mirror of the
                   source subtree (removes dest-only files). Destructive.
      --overwrite  Drop --update: let the backup overwrite newer live files.
      --from ROOT  Use ROOT as the snapshot data root (overrides env and sops).
  -h, --help       Show this help.

Exit codes: 0 ok, 2 usage, 3 source root not mounted, 4 a source path was absent.
EOF
}

die() { printf 'tm-restore: %s\n' "$1" >&2; exit "${2:-1}"; }

dry=0
mirror=0
overwrite=0
from=""
to=""
paths=()

while [ $# -gt 0 ]; do
  case "$1" in
    -n | --dry-run) dry=1 ;;
    --mirror) mirror=1 ;;
    --overwrite) overwrite=1 ;;
    --to)
      shift
      [ $# -gt 0 ] || die "--to requires an argument" 2
      to="$1"
      ;;
    --to=*) to="${1#*=}" ;;
    --from)
      shift
      [ $# -gt 0 ] || die "--from requires an argument" 2
      from="$1"
      ;;
    --from=*) from="${1#*=}" ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        paths+=("$1")
        shift
      done
      break
      ;;
    -*) die "unknown option: $1" 2 ;;
    *) paths+=("$1") ;;
  esac
  shift
done

if [ "${#paths[@]}" -eq 0 ]; then
  usage >&2
  exit 2
fi

if [ -n "$to" ] && [ "${#paths[@]}" -ne 1 ]; then
  die "--to requires exactly one source path" 2
fi

# Resolve the data root: --from > $TM_DATA_ROOT > contents of $TM_DATA_ROOT_FILE.
root="${from:-${TM_DATA_ROOT:-}}"
if [ -z "$root" ] && [ -n "${TM_DATA_ROOT_FILE:-}" ] && [ -r "${TM_DATA_ROOT_FILE:-}" ]; then
  root="$(cat "$TM_DATA_ROOT_FILE")"
fi
[ -n "$root" ] || die "no data root: pass --from, set \$TM_DATA_ROOT, or provision the sops secret" 2

if [ ! -d "$root" ]; then
  uuid=""
  case "$root" in
    /Volumes/.timemachine/*)
      rest="${root#/Volumes/.timemachine/}"
      uuid="${rest%%/*}"
      ;;
  esac
  {
    printf 'source root not mounted:\n  %s\n' "$root"
    if [ -n "$uuid" ]; then
      printf 'attach the archival source drive (volume %s) and mount its snapshot.\n' "$uuid"
    else
      printf 'attach the archival source drive and mount its snapshot.\n'
    fi
  } >&2
  exit 3
fi

rsync_opts=(-a --mkpath --partial --append-verify "--info=progress2,stats2" -h)
if [ "$overwrite" -ne 1 ]; then rsync_opts+=(--update); fi
if [ "$mirror" -eq 1 ]; then rsync_opts+=(--delete); fi
if [ "$dry" -eq 1 ]; then rsync_opts+=(-n -i); fi

status=0
zpaths=()
for src_path in "${paths[@]}"; do
  case "$src_path" in
    /*) : ;;
    *)
      printf 'tm-restore: skipping non-absolute path: %s\n' "$src_path" >&2
      status=4
      continue
      ;;
  esac
  src="${root}${src_path}"
  if [ -n "$to" ]; then
    out="$to"
  else
    out="$src_path"
  fi
  if [ -d "$src" ]; then
    printf '== %s\n   <- %s/\n' "$out" "$src" >&2
    if rsync "${rsync_opts[@]}" "$src/" "$out/"; then
      zpaths+=("$out")
    else
      status=1
    fi
  elif [ -e "$src" ]; then
    printf '== %s\n   <- %s\n' "$out" "$src" >&2
    rsync "${rsync_opts[@]}" "$src" "$out" || status=1
  else
    printf 'tm-restore: not in snapshot: %s\n' "$src" >&2
    status=4
  fi
done

# Register successfully-restored destination directories with zoxide (silent side
# effect, skipped under --dry-run since nothing is written). zoxide indexes
# directories, so only directory restores register a path.
if [ "$dry" -ne 1 ] && [ "${#zpaths[@]}" -gt 0 ]; then
  zoxide add "${zpaths[@]}" >/dev/null 2>&1 || true
fi

exit "$status"
