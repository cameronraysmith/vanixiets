#!/usr/bin/env bash
# Convert a hermes-backup tar.zst snapshot back to a hermes-import-compatible zip.
#
# Reads entries from <ARCHIVE.tar.zst> via bsdtar's `@archive` operand (which
# auto-decompresses zstd via libarchive's built-in filter), strips the
# hermes-<UTC-stamp>/ prefix injected by hermes-backup, and writes a standard
# zip with flat entry paths — matching the structure `hermes backup`
# originally produced. Optionally invokes `hermes import` on the result.
set -euo pipefail

input=""
output=""
do_import=0
force=0

usage() {
  cat <<'HELP'
usage: hermes-restore [-o OUTPUT_ZIP] [--import] [--force] <ARCHIVE.tar.zst>

Convert a hermes-backup tar.zst archive back into a hermes-import-compatible
zip file.

Arguments:
  <ARCHIVE.tar.zst>   Path to a tar.zst produced by hermes-backup (required)

Options:
  -o, --output PATH   Destination zip path (default: sibling of input with .zip)
  --import            Run `hermes import` on the resulting zip after producing it
  --force             Pass --force to hermes import (only relevant with --import)
  -h, --help          Show this help

Behavior:
  - Reads entries from <ARCHIVE> via bsdtar's @archive operand
    (auto-decompresses zstd via libarchive)
  - Strips the hermes-<UTC-stamp>/ top-level prefix
  - Writes the result as a standard zip via libarchive's zip writer
  - Verifies the zip listing before publishing via atomic rename
  - With --import: invokes `hermes import [--force] <zip>` after producing it
  - Temp dir cleaned on EXIT

Exit codes:
  0    archive converted (and imported if --import) successfully
  1    conversion or verification failure
  2    argument error
  127  hermes not found on PATH (only with --import)
HELP
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      [[ $# -ge 2 ]] || { echo "error: -o requires a PATH argument" >&2; exit 2; }
      output="$2"
      shift 2
      ;;
    --import)
      do_import=1
      shift
      ;;
    --force)
      force=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "error: unknown option '$1' (try --help)" >&2
      exit 2
      ;;
    *)
      if [[ -n "$input" ]]; then
        echo "error: unexpected positional argument '$1' (only one archive accepted)" >&2
        exit 2
      fi
      input="$1"
      shift
      ;;
  esac
done

[[ -n "$input" ]] || { echo "error: archive path required (try --help)" >&2; exit 2; }
[[ -f "$input" ]] || { echo "error: input not found: $input" >&2; exit 2; }

input=$(realpath "$input")

if [[ -z "$output" ]]; then
  case "$input" in
    *.tar.zst)
      output="${input%.tar.zst}.zip"
      ;;
    *)
      echo "error: cannot derive output: input '$input' does not end in .tar.zst" >&2
      echo "       use -o PATH to specify the output explicitly" >&2
      exit 2
      ;;
  esac
fi

first_entry=$(bsdtar -tf "$input" | head -1)
[[ -n "$first_entry" ]] || { echo "error: archive appears empty: $input" >&2; exit 1; }

stamp_prefix="${first_entry%%/*}"
case "$stamp_prefix" in
  hermes-*)
    ;;
  *)
    echo "error: archive does not have a hermes-<stamp>/ prefix dir (got '$stamp_prefix/')" >&2
    exit 1
    ;;
esac

if [[ "$do_import" -eq 1 ]]; then
  command -v hermes >/dev/null 2>&1 || {
    echo "error: hermes not found on PATH" >&2
    exit 127
  }
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bsdtar \
  --format zip \
  -cf "$tmp/output.zip" \
  -s "|^${stamp_prefix}/||" \
  "@$input"

bsdtar -tf "$tmp/output.zip" >/dev/null

first_out=$(bsdtar -tf "$tmp/output.zip" | head -1)
case "$first_out" in
  "${stamp_prefix}/"*)
    echo "error: prefix strip failed; output still contains '${stamp_prefix}/'" >&2
    exit 1
    ;;
esac

mkdir -p "$(dirname "$output")"
mv "$tmp/output.zip" "$output"

echo "$output"

if [[ "$do_import" -eq 1 ]]; then
  if [[ "$force" -eq 1 ]]; then
    hermes import --force "$output"
  else
    hermes import "$output"
  fi
fi
