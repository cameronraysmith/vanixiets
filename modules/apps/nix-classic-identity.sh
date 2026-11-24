#!/usr/bin/env bash
# shellcheck shell=bash

usage() {
  cat <<'EOF'
Usage: nix-classic-identity [--rev REV] [ATTR...]

Evaluates each ATTR of commit REV (default: the git HEAD of the current
repository) with stock `nix` and with iets' classic mode
(flake.lib.mkNixClassic), one after the other, and compares the drvPath
(`nix eval --raw ATTR.drvPath`) and the whole .drv closure (`nix derivation
show -r ATTR`, keys sorted). ATTRs default to the configurations people
evaluate: every darwinConfigurations.<host>.system,
nixosConfigurations.<host>.config.system.build.toplevel and
homeConfigurations.<name>.activationPackage, and devShells.<this
system>.default. Classic runs with the fallback off and the tracing cache
off, so a fallback is a failure and the times are full evaluations.
Prints one line per attribute with both times; exits 1 on any difference.
EOF
}

rev=""
attrs=()
while [ $# -gt 0 ]; do
  case $1 in
    --rev) rev=$2; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) attrs+=("$1"); shift ;;
  esac
done
repo=$(git rev-parse --show-toplevel)
[ -n "$rev" ] || rev=$(git -C "$repo" rev-parse HEAD)
rev=$(git -C "$repo" rev-parse --verify "$rev^{commit}")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# A clean checkout: iets evaluates local flakes only, and both evaluators must
# see the same tree, revision included.
git clone --quiet --shared --no-checkout "$repo" "$tmp/src"
git -C "$tmp/src" checkout --quiet --detach "$rev"
src=$tmp/src
# The wrapper evaluates with iets only where its marker exists; both
# evaluators run under this config home so they read the same user files.
mkdir -p "$tmp/config/nix-classic"
touch "$tmp/config/nix-classic/enabled"

if [ ${#attrs[@]} -eq 0 ]; then
  names() { "$NIX_STOCK" eval --json "$src#$1" --apply builtins.attrNames | jq -r '.[]'; }
  while read -r h; do attrs+=("darwinConfigurations.$h.system"); done < <(names darwinConfigurations)
  while read -r h; do attrs+=("nixosConfigurations.$h.config.system.build.toplevel"); done < <(names nixosConfigurations)
  while read -r h; do attrs+=("homeConfigurations.\"$h\".activationPackage"); done < <(names homeConfigurations)
  attrs+=("devShells.$("$NIX_STOCK" eval --impure --raw --expr builtins.currentSystem).default")
fi

seconds() { echo "$((${1} / 1000000)).$(((${1} / 100000) % 10))"; }

# run EVALUATOR OUT CMD...: CMD's stdout to OUT, its wall time in microseconds to stdout.
run() {
  local bin out=$2 start
  case $1 in
    stock) bin=$NIX_STOCK ;;
    classic) bin=$NIX_CLASSIC ;;
  esac
  shift 2
  start=${EPOCHREALTIME/./}
  if ! XDG_CONFIG_HOME=$tmp/config IETS_NIX_FALLBACK=never IETS_CACHE=0 "$bin" --option eval-cache false "$@" >"$out" 2>"$out.err"; then
    grep -v "accept-flake-config" "$out.err" | tail -3 >&2
    return 1
  fi
  echo $((${EPOCHREALTIME/./} - start))
}

failed=0
printf '%-72s %-8s %8s %8s %8s %8s %6s\n' attribute result "stock s" "iets s" "stock-r" "iets-r" drvs
for attr in "${attrs[@]}"; do
  ref="$src#$attr"
  result=identical
  for e in stock classic; do
    if ! t=$(run "$e" "$tmp/$e.drv" eval --raw "$ref.drvPath"); then result="$e-failed"; break; fi
    printf -v "eval_$e" %s "$(seconds "$t")"
    if ! t=$(run "$e" "$tmp/$e.json" derivation show -r "$ref"); then result="$e-failed"; break; fi
    printf -v "closure_$e" %s "$(seconds "$t")"
    jq -S . "$tmp/$e.json" >"$tmp/$e.sorted"
  done
  drvs=-
  if [ "$result" = identical ]; then
    drvs=$(jq '.derivations | length' "$tmp/stock.sorted")
    if ! cmp -s "$tmp/stock.drv" "$tmp/classic.drv"; then
      result=drvPath-differs
    elif ! cmp -s "$tmp/stock.sorted" "$tmp/classic.sorted"; then
      result=closure-differs
      diff <(jq -r '.derivations | keys[]' "$tmp/stock.sorted") <(jq -r '.derivations | keys[]' "$tmp/classic.sorted") | head -5 >&2
    fi
  fi
  [ "$result" = identical ] || failed=1
  printf '%-72s %-8s %8s %8s %8s %8s %6s\n' "$attr" "$result" "${eval_stock:--}" "${eval_classic:--}" \
    "${closure_stock:--}" "${closure_classic:--}" "$drvs"
  unset eval_stock eval_classic closure_stock closure_classic
done
echo "at ${rev:0:12}; stock/iets s: nix eval --raw .drvPath; stock-r/iets-r: nix derivation show -r"
exit "$failed"
