# Claude Code cloud environment setup for the claude-sandbox profile. The setup
# box's bootstrap (claude-sandbox-setup.nix) runs it from main; the .nix defines
# R, C, S and K above this text from lib/caches.nix.
#
# Three stages, composed at the bottom:
#   choose    the closure: the pinned path, or main's newest published one;
#   realise   it from the caches without building;
#   activate  it, unless it is already the current generation.
# The marker in setup.log is the one projection of their results, and the script
# always exits 0: a non-zero setup step stops the session from starting (A170).

# One word each: the Q97 probe saw an unquoted list split into arguments.
O=(--option substituters "${S[*]}" --option trusted-public-keys "${K[*]}" --option accept-flake-config false)
A='homeConfigurations."claude-sandbox@x86_64-linux".activationPackage.outPath'
L=/var/log/claude-sandbox-bootstrap

# Prints one outcome and writes nothing but run.log:
#   pinned <path> | tracked <path> <rev> <dist> <tip> <skips> | none <tip> <skips>
# Without a pin it walks main's 5 newest first-parent commits from the tip, for
# at most about 300 s, and takes the first whose activation package evaluates and
# whose narinfo the fleet cache serves; each skip is <rev>:eval/<code>,
# <rev>:narinfo or <rev>:budget.
choose() {
  local pin=$1 deadline tip=none skips='' i=0 d c p left
  if [ -n "$pin" ]; then
    echo "pinned $pin"
    return
  fi
  deadline=$(($(date +%s) + 300))
  d=$(mktemp -d)
  # main's 5 newest commit objects only; the plain shallow clone if the filter is refused.
  timeout 60 git clone -q --bare --depth 5 --filter=tree:0 --single-branch -b main "$R" "$d" >>"$L/run.log" 2>&1 ||
    timeout 120 git clone -q --bare --depth 5 --single-branch -b main "$R" "$d" >>"$L/run.log" 2>&1
  for c in $(git -C "$d" rev-list --first-parent -n 5 main 2>>"$L/run.log"); do
    [ "$i" = 0 ] && tip=$c
    i=$((i + 1))
    left=$((deadline - $(date +%s)))
    [ "$left" -gt 0 ] || { skips="$skips,${c:0:12}:budget"; break; }
    p=$(timeout "$left" nix eval --raw "${O[@]}" "git+$R?rev=$c&shallow=1#$A" 2>>"$L/run.log") ||
      { skips="$skips,${c:0:12}:eval/$?"; continue; }
    if nix path-info --store "$C" --option narinfo-cache-negative-ttl 0 "$p" >/dev/null 2>>"$L/run.log"; then
      rm -rf "$d"
      echo "tracked $p $c $((i - 1)) $tip ${skips:-,}"
      return
    fi
    skips="$skips,${c:0:12}:narinfo"
  done
  rm -rf "$d"
  echo "none $tip ${skips:-,}"
}

# Fetches a closure from the two caches and returns the realise's code; a path
# neither cache serves fails instead of building (--max-jobs 0).
realise() {
  timeout 600 nix-store -r "$1" --max-jobs 0 --option builders '' "${O[@]}" >>"$L/run.log" 2>&1
}

# Prints skipped (no path), current (already the current generation, so a second
# setup run on first use leaves /root alone, A171) or the activation's code.
activate() {
  if [ -z "$1" ]; then
    echo skipped
  elif [ "$(readlink -f /root/.local/state/home-manager/gcroots/current-home)" = "$1" ]; then
    echo current
  else
    USER=root HOME=/root timeout 240 "$1/activate" >>"$L/run.log" 2>&1
    echo $?
  fi
}

mkdir -p "$L"
t0=$(date +%s)
read -r mode path f2 f3 f4 f5 <<<"$(choose "${1:-}")"
case $mode in
  pinned) rev=none dist=none tip=none skips=, ;;
  tracked) rev=$f2 dist=$f3 tip=$f4 skips=$f5 ;;
  *) mode=none tip=${path:-none} skips=${f2:-,} path='' rev=none dist=none ;;
esac
t1=$(date +%s) rr=skipped ready=''
if [ -n "$path" ]; then
  realise "$path"
  rr=$?
  [ "$rr" = 0 ] && ready=$path
fi
t2=$(date +%s)
ar=$(activate "$ready")
t3=$(date +%s)
echo "$(date -u +%FT%TZ) mode=$mode tip=$tip rev=$rev dist=$dist skip=${skips#,} select=$((t1 - t0))s" \
  "realise=$rr/$((t2 - t1))s activate=$ar/$((t3 - t2))s nix=$(nix-store --version | awk '{print $NF}') P=${path:-none}" >>"$L/setup.log"
exit 0
