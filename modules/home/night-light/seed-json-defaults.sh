# seed-json-defaults TARGET MARKER DEFAULTS [SETTLE...]
#
# Adds the keys of the JSON object in DEFAULTS that TARGET lacks, once: when
# MARKER exists nothing is touched, so a value the user later changes, or
# that the application deletes for equalling its own default, is never
# written back. A missing TARGET is created holding DEFAULTS; the existing
# file's keys win over the defaults.
#
# SETTLE, when given, runs after TARGET is written and must succeed before
# MARKER is created: it makes a running application take up the file instead
# of saving its in-memory state over it. A failing SETTLE, or a TARGET that is
# not a JSON object (left unchanged), withholds MARKER so the next run retries;
# neither fails the caller.
target=$1
marker=$2
defaults=$3
shift 3

[ -e "$marker" ] && exit 0

mkdir -p "$(dirname "$target")" "$(dirname "$marker")"

if [ -e "$target" ]; then
  if ! jq -e 'type == "object"' "$target" > /dev/null 2>&1; then
    echo "seed-json-defaults: $target is not a JSON object; left unchanged, will retry" >&2
    exit 0
  fi
  tmp=$(mktemp "$target.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
  jq --slurpfile defaults "$defaults" '$defaults[0] + .' "$target" > "$tmp"
  chmod --reference="$target" "$tmp"
  mv "$tmp" "$target"
  trap - EXIT
else
  jq . "$defaults" > "$target"
fi

if [ $# -gt 0 ] && ! "$@"; then
  echo "seed-json-defaults: $target seeded but '$*' failed; will retry" >&2
  exit 0
fi
touch "$marker"
echo "seed-json-defaults: seeded $target"
