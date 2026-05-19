#!/usr/bin/env bash
# Snapshot hermes-agent state to a prefix-directory tar.zst archive.
#
# Invokes `hermes backup -o <tmp>.zip` to produce an intermediate zip,
# then re-wraps it into <out_dir>/hermes-<UTC-stamp>.tar.zst with every
# entry prefixed by hermes-<UTC-stamp>/ so extraction does not explode
# into cwd. Verifies the archive listing before atomic-renaming into
# place; the EXIT trap removes the temp directory (and intermediate zip)
# on either success or failure.
set -euo pipefail

out_dir="${HOME}/backups/hermes"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      [[ $# -ge 2 ]] || { echo "error: -o requires a DIR argument" >&2; exit 2; }
      out_dir="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'HELP'
usage: hermes-backup [-o OUTPUT_DIR]

Snapshot hermes-agent state into a date-stamped tar.zst archive.

Options:
  -o, --output DIR   Destination directory (default: ~/backups/hermes)
  -h, --help         Show this help

Behavior:
  - Runs `hermes backup` to produce an intermediate zip in a temp dir.
  - Re-wraps the zip into <DIR>/hermes-<UTC-stamp>.tar.zst with every
    entry prefixed by hermes-<UTC-stamp>/ so extraction stays contained.
  - Verifies the archive listing before publishing the artifact via
    atomic rename. Temp dir (and intermediate zip) cleaned on EXIT.

Exit codes:
  0    archive written and verified
  1    hermes-backup invocation or verification failure
  2    argument error
  127  hermes not found on PATH
HELP
      exit 0
      ;;
    *)
      echo "error: unknown argument '$1' (try --help)" >&2
      exit 2
      ;;
  esac
done

command -v hermes >/dev/null 2>&1 || {
  echo "error: hermes not found on PATH" >&2
  exit 127
}

stamp=$(date -u +%Y%m%dT%H%M%SZ)
name="hermes-${stamp}"

mkdir -p "$out_dir"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

hermes backup -o "$tmp/${name}.zip"

bsdtar \
  --use-compress-program "zstd -T0 --long=27 -19" \
  -cf "$tmp/${name}.tar.zst" \
  -s "|^|${name}/|" \
  -C "$tmp" \
  "${name}.zip"

bsdtar -tf "$tmp/${name}.tar.zst" >/dev/null

mv "$tmp/${name}.tar.zst" "$out_dir/${name}.tar.zst"

echo "$out_dir/${name}.tar.zst"
