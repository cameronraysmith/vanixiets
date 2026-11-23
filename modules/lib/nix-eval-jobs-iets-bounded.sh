# nix-eval-jobs over iets (flake.lib.mkNixEvalJobsIetsBounded): iets'
# nix-eval-jobs with its worker count bounded by NIX_EVAL_JOBS_IETS_WORKERS
# and, where set, its per-worker memory by NIX_EVAL_JOBS_IETS_MAX_MEMORY_SIZE
# (MiB): each is the default when the caller gives none and the ceiling when
# it asks for more. iets cannot bound a worker's memory on macOS
# (--max-memory-size reads /proc), so there the worker count is the only
# bound and the memory variable is unset. Every other argument is passed
# through.
args=()
workers=""
memory=""
while [ $# -gt 0 ]; do
  case $1 in
    --workers | --max-memory-size)
      [ $# -ge 2 ] || { echo "nix-eval-jobs: $1 needs a value" >&2; exit 2; }
      if [ "$1" = --workers ]; then workers=$2; else memory=$2; fi
      shift 2
      ;;
    --workers=*)
      workers=${1#--workers=}
      shift
      ;;
    --max-memory-size=*)
      memory=${1#--max-memory-size=}
      shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

# bound NAME VALUE CEILING: VALUE, or CEILING when VALUE is empty or above it.
# 0 is above every ceiling: for --max-memory-size it means no limit.
bound() {
  case $2 in
    "") echo "$3" ;;
    *[!0-9]*) echo "nix-eval-jobs: $1 must be a non-negative integer, got '$2'" >&2; exit 2 ;;
    *)
      if [ "$2" -eq 0 ] || [ "$2" -gt "$3" ]; then
        echo "nix-eval-jobs: $1 $2 requested, $3 used (this host's bound for iets)" >&2
        echo "$3"
      else
        echo "$2"
      fi
      ;;
  esac
}

workers=$(bound --workers "$workers" "$NIX_EVAL_JOBS_IETS_WORKERS") || exit
if [ -n "${NIX_EVAL_JOBS_IETS_MAX_MEMORY_SIZE:-}" ]; then
  memory=$(bound --max-memory-size "$memory" "$NIX_EVAL_JOBS_IETS_MAX_MEMORY_SIZE") || exit
fi
exec "$NIX_EVAL_JOBS_IETS" --workers "$workers" ${memory:+--max-memory-size "$memory"} "${args[@]}"
