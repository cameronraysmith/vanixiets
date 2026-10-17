# ghq that defers to a host-shared, read-only ghq tree when, and only when, the
# caller's effective ghq root is that tree. Then read-only subcommands run
# nixpkgs ghq directly and `get` is carried out by the tree's writer account,
# one request per target; an unreachable writer fails. For any other root this
# is plain nixpkgs ghq, so it is safe on a PATH outside a sharing host.

real=@ghq@
client=@client@
shared_root=@root@
git=@git@
realpath=@realpath@

refuse() {
  printf 'ghq: %s\n' "$1" >&2
  exit 2
}

# ghq's own precedence: a nonempty GHQ_ROOT (first entry) wins over the last
# ghq.root in git configuration.
if [ -n "${GHQ_ROOT:-}" ]; then
  effective_root=${GHQ_ROOT%%:*}
else
  effective_root=$("$git" config --path --get ghq.root 2>/dev/null || true)
fi
if [ -z "$effective_root" ] \
  || [ "$("$realpath" -m -- "$effective_root")" != "$("$realpath" -m -- "$shared_root")" ]; then
  exec "$real" "$@"
fi

if [ "$#" -eq 0 ]; then
  exec "$real"
fi

case "$1" in
  -h | --help | -v | --version | help | h | list | root)
    exec "$real" "$@"
    ;;
  get) shift ;;
  create | rm | migrate)
    refuse "$1 is unavailable: this host's ghq tree is shared and only its writer account changes it"
    ;;
  *)
    refuse "unsupported on a shared ghq tree: $1"
    ;;
esac

lazy=0
update=0
targets=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --shallow) lazy=1 ;;
    --partial)
      [ "${2:-}" = blobless ] || refuse "only --partial blobless is supported"
      shift
      ;;
    --partial=blobless) ;;
    --no-recursive | -P | --parallel | -s | --silent) ;;
    -u | --update) update=1 ;;
    --)
      shift
      targets+=("$@")
      break
      ;;
    -*) refuse "unsupported get option on a shared ghq tree: $1" ;;
    *) targets+=("$1") ;;
  esac
  shift
done

if [ "${#targets[@]}" -eq 0 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && targets+=("$line")
  done
fi

flags=()
if [ "$lazy" = 1 ]; then flags+=(--lazy); fi
if [ "$update" = 1 ]; then flags+=(--update); fi

# A directory inside the shared root names the repository that contains it, as
# host/owner/repo; the writer only ever receives that form. An explicit path
# outside the root is an error; a bare name that happens to exist locally is a
# ghq target, as it is for ghq itself.
root_real=$("$realpath" -m -- "$shared_root")
normalize() {
  local target=$1 dir
  if [ ! -d "$target" ]; then
    printf '%s\n' "$target"
    return 0
  fi
  dir=$("$realpath" -- "$target")
  case "$dir/" in
    "$root_real"/*/) ;;
    *)
      case "$target" in
        . | .. | /* | ./* | ../*)
          refuse "$target is outside the shared ghq root $shared_root"
          ;;
      esac
      printf '%s\n' "$target"
      return 0
      ;;
  esac
  while [ "$dir" != "$root_real" ] && [ ! -e "$dir/.git" ]; do
    dir=$(dirname -- "$dir")
  done
  [ "$dir" != "$root_real" ] || refuse "$target is not inside a repository under $shared_root"
  printf '%s\n' "${dir#"$root_real"/}"
}

resolved=()
for target in "${targets[@]}"; do
  resolved+=("$(normalize "$target")") || exit 2
done

rc=0
for target in "${resolved[@]}"; do
  "$client" get "${flags[@]}" "$target" || rc=$?
done
exit "$rc"
