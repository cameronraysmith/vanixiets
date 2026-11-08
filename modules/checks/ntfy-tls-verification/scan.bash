# scan.bash TREE CLIENTS NONCLIENTS EXEMPT CLAUSE...
# Judges the source tree TREE for ntfy.zt clients. CLIENTS, NONCLIENTS and
# EXEMPT are files listing tree-relative paths, one per line (NONCLIENTS as
# "<path>\t<reason>"). CLAUSE is any of A, B, C. Prints "FAIL <clause>: …" for
# each finding and exits 1 if any clause failed.
set -uo pipefail
tree=$1 clients=$2 nonclients=$3 exempt=$4
shift 4
cd "$tree"
fail=0
named=$(grep -rlF --include='*.sh' --include='*.bash' --include='*.nix' --include='*.py' --include='*.ts' --include='*.js' 'ntfy.zt' modules pkgs | LC_ALL=C sort)
# The left boundary admits `_` and `-`, so "${NTFY_CURL_BIN:-curl}" counts as invoking curl.
invokes='(^|[^A-Za-z0-9])(curl|wget|CURL_BIN)([^A-Za-z0-9_]|$)'
insecure='(^|[[:space:]"'"'"'])(-[A-Za-z]*k[A-Za-z]*|--insecure)([[:space:]"'"'"']|$)'
# logical FILE: prints "FILE:LINE: <command line with continuations joined>",
# LINE being the command's first line.
logical() {
  awk '{ if (buf == "") start = FNR; line = $0; if (sub(/\\[[:space:]]*$/, "", line)) { buf = buf line " "; next } print FILENAME ":" start ": " buf line; buf = "" }' "$1"
}
listed() { cut -f1 "$1" | grep -qxF "$2"; }
for clause in "$@"; do
  case $clause in
    A)
      for f in $named; do
        listed "$exempt" "$f" && continue
        hits=$(logical "$f" | grep -E "$invokes" | grep -E -- "$insecure")
        [ -z "$hits" ] || { printf 'FAIL A: %s\n' "$hits"; fail=1; }
      done ;;
    B)
      while IFS= read -r c; do
        [ -n "$c" ] || continue
        if [ ! -f "$c" ]; then echo "FAIL B: declared client $c is missing"; fail=1
        elif ! grep -qF -- '--cacert' "$c"; then echo "FAIL B: declared client $c passes no --cacert"; fail=1; fi
      done < "$clients" ;;
    C)
      for f in $named; do
        grep -qE "$invokes" "$f" || continue
        listed "$clients" "$f" || listed "$nonclients" "$f" || listed "$exempt" "$f" || { echo "FAIL C: $f names ntfy.zt and invokes curl or wget but is not declared"; fail=1; }
      done ;;
  esac
done
exit $fail
