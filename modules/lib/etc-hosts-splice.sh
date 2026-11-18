# shellcheck shell=bash
# Body of etc-hosts-splice (modules/lib/etc-hosts-splice.nix): replace the
# block between the marker lines in a hosts file with the contents of a block
# file, leaving every other line as it was.
#
# Usage: etc-hosts-splice <hosts file> <block file>
#
# An empty block file removes the block and its markers. A missing hosts file
# counts as empty. The new file is written beside the old one and renamed over
# it, keeping the old file's owner and mode, so a reader sees either the old or
# the new file, and the rename is the change mDNSResponder's watch on
# /etc/hosts sees: it opens the file and re-reads it when that file is
# deleted, renamed or written (mDNSResponder-2600.140.3
# mDNSMacOSX/mDNSMacOSX.c:5979-6052). When the result equals the current
# file nothing is written.
#
# Markers that do not pair up (a BEGIN without its END, an END without a
# BEGIN, a BEGIN inside a block) leave the file untouched and exit 2, since
# stripping from an unclosed BEGIN would delete every line after it.

hosts=$1
block=$2
begin='# BEGIN vanixiets hosts (generated on activation; edits inside are replaced)'
end='# END vanixiets hosts'

current=$(mktemp)
next=
cleanup() {
  rm -f "$current"
  if [ -n "$next" ]; then rm -f "$next"; fi
}
trap cleanup EXIT

if [ -e "$hosts" ]; then
  cat "$hosts" >"$current"
fi

if ! awk -v begin="$begin" -v end="$end" '
  $0 == begin { if (inside) bad = 1; inside = 1; next }
  $0 == end   { if (!inside) bad = 1; inside = 0; next }
  END         { exit (bad || inside) }
' "$current"; then
  echo "etc-hosts-splice: unpaired marker lines in $hosts; left unchanged" >&2
  exit 2
fi

next=$(mktemp "$hosts.vanixiets.XXXXXX")
{
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { inside = 1; next }
    $0 == end   { inside = 0; next }
    !inside     { print }
  ' "$current"
  if [ -s "$block" ]; then
    printf '%s\n' "$begin"
    cat "$block"
    printf '%s\n' "$end"
  fi
} >"$next"

if [ -e "$hosts" ] && cmp -s "$next" "$hosts"; then
  exit 0
fi

if [ -e "$hosts" ]; then
  chown --reference="$hosts" "$next"
  chmod --reference="$hosts" "$next"
else
  chmod 0644 "$next"
fi
mv -f "$next" "$hosts"
next=
