# ghq for an account that reads a host-shared, read-only ghq tree.
# Read-only subcommands run nixpkgs ghq directly; `get` is carried out by the
# tree's writer account, one request per target.

real=@ghq@
client=@client@

refuse() {
  printf 'ghq: %s\n' "$1" >&2
  exit 2
}

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

rc=0
for target in "${targets[@]}"; do
  "$client" get "${flags[@]}" "$target" || rc=$?
done
exit "$rc"
