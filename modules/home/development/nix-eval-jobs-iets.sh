# nix-eval-jobs-iets: iets' nix-eval-jobs (flake.lib.mkNixEvalJobsIets) with
# its worker count bounded by NIX_EVAL_JOBS_IETS_WORKERS, the default when the
# caller gives no --workers and the ceiling when it asks for more. iets cannot
# bound a worker's memory on macOS (--max-memory-size reads /proc), so the
# worker count is the only bound there. Every other argument is passed through.
args=()
workers=""
while [ $# -gt 0 ]; do
  case $1 in
    --workers)
      [ $# -ge 2 ] || { echo "nix-eval-jobs-iets: --workers needs a value" >&2; exit 2; }
      workers=$2
      shift 2
      ;;
    --workers=*)
      workers=${1#--workers=}
      shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done
case $workers in
  "") workers=$NIX_EVAL_JOBS_IETS_WORKERS ;;
  *[!0-9]* | 0) echo "nix-eval-jobs-iets: --workers must be a positive integer, got '$workers'" >&2; exit 2 ;;
  *)
    if [ "$workers" -gt "$NIX_EVAL_JOBS_IETS_WORKERS" ]; then
      echo "nix-eval-jobs-iets: $workers workers requested, $NIX_EVAL_JOBS_IETS_WORKERS used (this host's bound; iets cannot bound worker memory on macOS)" >&2
      workers=$NIX_EVAL_JOBS_IETS_WORKERS
    fi
    ;;
esac
exec "$NIX_EVAL_JOBS_IETS" --workers "$workers" "${args[@]}"
