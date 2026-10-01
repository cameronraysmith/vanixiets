# managed-config SPEC.json [SPEC.json ...]
#
# Writes each spec's target as its declared content plus the spec's appOwned
# key paths copied from the existing file, and reports on stderr, by name only,
# the leaf paths the old file had that the new one lacks (externalPaths
# excluded). Paths are dotted; keys containing dots are unsupported.
# shellcheck disable=SC2016

if [ "$#" -eq 0 ]; then
  echo "usage: managed-config SPEC.json [SPEC.json ...]" >&2
  exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# An empty or whitespace-only file reads as an empty mapping; anything else
# that is not exactly one mapping (including an explicit null) is unreadable.
read_target() {
  local format=$1 target=$2 out=$3
  if [ -z "$(tr -d '[:space:]' < "$target")" ]; then
    echo '{}' > "$out"
    return 0
  fi
  yq -p "$format" -o json -I0 '.' "$target" > "$out.docs" 2> /dev/null || return 1
  jq -cs '
    if length == 1 and (.[0] | type) == "object" then .[0]
    else error("not a mapping") end
  ' "$out.docs" > "$out" 2> /dev/null
}

process() {
  local spec=$1 name target format declared mode app_owned external dir tmp dropped
  local old="$work/old.json" merged="$work/merged.json" have_old=0

  if ! name="$(jq -er '.name | strings' "$spec")" \
    || ! target="$(jq -er '.target | strings' "$spec")" \
    || ! format="$(jq -er '.format | strings' "$spec")" \
    || ! declared="$(jq -er '.declared | strings' "$spec")" \
    || ! mode="$(jq -er '.fileMode // "0644" | strings' "$spec")" \
    || ! app_owned="$(jq -ce '.appOwned // [] | arrays' "$spec")" \
    || ! external="$(jq -ce '.externalPaths // [] | arrays' "$spec")"; then
    echo "managed-config: invalid spec $spec" >&2
    return 1
  fi
  case "$format" in
    json | yaml | toml) ;;
    *)
      echo "managed-config $name: unsupported format $format" >&2
      return 1
      ;;
  esac
  case "$target" in
    /*) ;;
    *)
      echo "managed-config $name: target $target is not absolute" >&2
      return 1
      ;;
  esac

  rm -f "$old" "$merged"
  if [ -e "$target" ]; then
    if read_target "$format" "$target" "$old"; then
      have_old=1
    elif [ "$app_owned" != "[]" ]; then
      echo "managed-config $name: $target is unreadable or not a mapping; left untouched" >&2
      return 1
    else
      echo "managed-config $name: replaced unreadable $target" >&2
    fi
  fi

  if [ "$have_old" = 1 ]; then
    jq -n --slurpfile d "$declared" --slurpfile o "$old" --argjson own "$app_owned" '
      def present($p):
        if ($p | length) == 0 then true
        elif type == "object" and has($p[0]) then .[$p[0]] | present($p[1:])
        else false end;
      $o[0] as $old
      | reduce ($own[] | split(".")) as $p ($d[0];
          if $old | present($p) then setpath($p; $old | getpath($p)) else . end)
    ' > "$merged" || {
      echo "managed-config $name: failed to merge $declared" >&2
      return 1
    }
    dropped="$(jq -rn --slurpfile n "$merged" --slurpfile o "$old" --argjson ext "$external" '
      def leaves: paths(if type == "object" or type == "array" then length == 0 else true end);
      def norm: map(if type == "number" then "[]" else "." + . end) | join("") | ltrimstr(".");
      ($ext | map(split("."))) as $prefixes
      | ([$n[0] | leaves | norm] | unique) as $kept
      | [$o[0] | leaves
          | select(. as $p | $prefixes | all(. as $e | $p[0:($e | length)] != $e))
          | norm]
      | unique - $kept
      | join(", ")
    ')" || {
      echo "managed-config $name: failed to compare $target" >&2
      return 1
    }
    if [ -n "$dropped" ]; then
      echo "managed-config $name: dropped undeclared keys: $dropped" >&2
    fi
  else
    jq '.' "$declared" > "$merged" || {
      echo "managed-config $name: unreadable declared content $declared" >&2
      return 1
    }
  fi

  dir="$(dirname "$target")"
  mkdir -p "$dir" || {
    echo "managed-config $name: cannot create $dir" >&2
    return 1
  }
  tmp="$(mktemp "$dir/.$(basename "$target").managed-config.XXXXXX")" || {
    echo "managed-config $name: cannot create a temporary file in $dir" >&2
    return 1
  }
  if ! yq -p json -o "$format" '.' "$merged" > "$tmp" \
    || ! chmod "$mode" "$tmp" \
    || ! mv -f "$tmp" "$target"; then
    rm -f "$tmp"
    echo "managed-config $name: failed to write $target" >&2
    return 1
  fi
}

status=0
for spec in "$@"; do
  process "$spec" || status=1
done
exit "$status"
