#!/usr/bin/env bash
# List the chain bookmarks in the current jj development join sorted by tip
# timestamp.
#
# Reads the parents of @- (= the chain tips of the current N-way development
# join) and prints one row per chain with its tip timestamp, bookmark(s), and
# (optionally) description first line. Sort key and direction are configurable.
#
# Pre-conditions (each with a distinct exit code, see help text):
#  - cwd inside jj repo (10)
#  - @- has >= 2 parents (17)
#
# Exit codes:
#  0   success
#  1   usage / unknown flag / invalid value
#  10  not inside a jj repo
#  17  @- has fewer than 2 parents (not a development join)
set -euo pipefail

show_help() {
  cat <<'HELP'
List the chain bookmarks in the current jj development join sorted by tip timestamp.

Usage:
  jj-join-chains [OPTIONS]
  jj-join-chains test [SCENARIO]
  jj-join-chains --help

Reads the parents of @- (= the chain tips of the current N-way development
join) and prints one row per chain with its tip timestamp, bookmark(s), and
description first line. Sort key and direction are configurable.

Options:
  --sort-key {committer|author}   Which timestamp drives the sort (default: committer)
  --order {desc|asc}              Sort direction (default: desc — most recent first)
  --limit N                       Show only the top N rows after sort
  --format {human|tsv}            Output format (default: human)
  --include-description           Force-include the description column (default for human)
  --no-description                Omit the description column in human mode (no-op for tsv)
  -h, --help                      Show this help message

Subcommand:
  test [SCENARIO]                 Run embedded self-tests. SCENARIO is one of:
                                    no-jj-repo, single-parent-fails, two-chain-desc,
                                    two-chain-asc, anonymous-parent, limit,
                                    tsv-format
                                  Omit SCENARIO to run all.

Exit codes:
  0    success
  1    usage / unknown flag / invalid value
  10   not inside a jj repo
  17   @- has fewer than 2 parents (not a development join)

Examples:
  jj-join-chains
  jj-join-chains --order asc --limit 3
  jj-join-chains --format tsv | rg jj-keep-remaining
  jj-join-chains --limit 1   # what's the most recently advanced chain?
HELP
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

# Default values
sort_key="committer"
order_dir="desc"
limit=""
format="human"
# include_description: empty = format default (human=yes, tsv=yes); "true" / "false"
# explicit override.
include_description=""
test_mode=false
test_scenario=""

if [[ "${1:-}" == "test" ]]; then
  test_mode=true
  shift
  test_scenario="${1:-}"
  set --
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    --sort-key)
      sort_key="${2:-}"
      if [[ "${sort_key}" != "committer" && "${sort_key}" != "author" ]]; then
        echo "Error: --sort-key must be 'committer' or 'author' (got '${sort_key}')." >&2
        exit 1
      fi
      shift 2
      ;;
    --order)
      order_dir="${2:-}"
      if [[ "${order_dir}" != "desc" && "${order_dir}" != "asc" ]]; then
        echo "Error: --order must be 'desc' or 'asc' (got '${order_dir}')." >&2
        exit 1
      fi
      shift 2
      ;;
    --limit)
      limit="${2:-}"
      if ! [[ "${limit}" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: --limit must be a positive integer (got '${limit}')." >&2
        exit 1
      fi
      shift 2
      ;;
    --format)
      format="${2:-}"
      if [[ "${format}" != "human" && "${format}" != "tsv" ]]; then
        echo "Error: --format must be 'human' or 'tsv' (got '${format}')." >&2
        exit 1
      fi
      shift 2
      ;;
    --include-description) include_description="true"; shift ;;
    --no-description) include_description="false"; shift ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      echo "Try 'jj-join-chains --help' for more information." >&2
      exit 1
      ;;
    *)
      echo "Error: Unexpected argument: $1" >&2
      echo "Try 'jj-join-chains --help' for more information." >&2
      exit 1
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

in_jj_repo() {
  jj --ignore-working-copy root >/dev/null 2>&1
}

# Count parents of @- (newline-separated, blank lines stripped).
parents_of_at_minus_count() {
  jj --ignore-working-copy log -r 'parents(@-)' --no-graph -T 'change_id ++ "\n"' 2>/dev/null \
    | sed '/^$/d' | wc -l | tr -d ' '
}

# -----------------------------------------------------------------------------
# Pre-condition checks
# -----------------------------------------------------------------------------

precondition_checks() {
  # 10: inside a jj repo
  if ! in_jj_repo; then
    echo "Error (precondition 10): current directory is not inside a jj repository." >&2
    exit 10
  fi

  # 17: @- must have >= 2 parents
  local parent_count
  parent_count=$(parents_of_at_minus_count)
  if [[ "${parent_count}" -lt 2 ]]; then
    echo "Error (precondition 17): @- has ${parent_count} parents; expected >= 2 for a development join." >&2
    exit 17
  fi
}

# -----------------------------------------------------------------------------
# Listing core
# -----------------------------------------------------------------------------

# Emit timestamp-first rows for parents(@-) using the configured sort key.
# Each row: <timestamp>\t<bookmarks-or-anonymous>\t<short_change_id>\t<description-first-line>
emit_rows_raw() {
  local ts_field
  if [[ "${sort_key}" == "author" ]]; then
    ts_field='author.timestamp()'
  else
    ts_field='committer.timestamp()'
  fi
  # Template: timestamp, then tab-separated fields. Use a literal tab via "\t".
  local tmpl
  tmpl="${ts_field} ++ \"\\t\" ++ if(bookmarks, bookmarks.join(\",\"), \"(\" ++ change_id.short() ++ \")\") ++ \"\\t\" ++ change_id.short() ++ \"\\t\" ++ description.first_line() ++ \"\\n\""
  jj --ignore-working-copy log -r 'parents(@-)' --no-graph -T "${tmpl}" 2>/dev/null \
    | sed -e 's/\r$//' \
    | awk -F'\t' 'NF>=4 { gsub(/\t/, " ", $4); print $1 "\t" $2 "\t" $3 "\t" $4 }' \
    | sed '/^[[:space:]]*$/d'
}

# Apply sort + limit to the raw rows.
sort_and_limit() {
  local sort_flags=()
  if [[ "${order_dir}" == "desc" ]]; then
    sort_flags=(-r)
  fi
  if [[ -n "${limit}" ]]; then
    sort "${sort_flags[@]}" | head -n "${limit}"
  else
    sort "${sort_flags[@]}"
  fi
}

# Render the sorted+limited rows in the requested format.
render_output() {
  local show_desc
  if [[ "${format}" == "tsv" ]]; then
    show_desc="true"
  elif [[ -n "${include_description}" ]]; then
    show_desc="${include_description}"
  else
    show_desc="true"
  fi

  local timestamp bookmarks short_id desc
  while IFS=$'\t' read -r timestamp bookmarks short_id desc; do
    [[ -z "${timestamp}" ]] && continue
    if [[ "${format}" == "tsv" ]]; then
      printf '%s\t%s\t%s\t%s\n' "${timestamp}" "${bookmarks}" "${short_id}" "${desc}"
    else
      if [[ "${show_desc}" == "true" ]]; then
        printf '%s  %s  %s\n' "${timestamp}" "${bookmarks}" "${desc}"
      else
        printf '%s  %s\n' "${timestamp}" "${bookmarks}"
      fi
    fi
  done
}

print_chains() {
  emit_rows_raw | sort_and_limit | render_output
}

# -----------------------------------------------------------------------------
# Test scenarios
# -----------------------------------------------------------------------------

# Reset globals between scenarios so leftover state cannot leak.
reset_globals() {
  sort_key="committer"
  order_dir="desc"
  limit=""
  format="human"
  include_description=""
}

# Build a diamond with `n` chains. If `anonymous_index` is set (1-based), that
# chain's bookmark is NOT created (leaving an anonymous parent).
scenario_setup_diamond() {
  local n="$1"; shift
  local anonymous_index="${1:-0}"; shift || true

  local tmpdir
  tmpdir=$(mktemp -d -t jj-join-chains-test.XXXXXX)
  echo "${tmpdir}"
  cd "${tmpdir}"

  jj git init >/dev/null 2>&1
  echo "base" > base.txt
  jj describe -m "init" >/dev/null
  jj bookmark create main -r @ >/dev/null
  jj new -m "stash" >/dev/null

  local i
  local parent_revs=()
  for ((i=1; i<=n; i++)); do
    jj new main -m "chain ${i} commit" >/dev/null
    echo "content-${i}" > "file-${i}.txt"
    # Capture the change-id of this chain's tip directly from @ before any
    # bookmark creation, since the description() revset has subtle quoting/
    # syntax differences across jj versions.
    local rev
    rev=$(jj --ignore-working-copy log -r @ --no-graph -T 'change_id ++ "\n"' --limit 1 2>/dev/null | head -1)
    parent_revs+=("${rev}")
    if [[ "${i}" -ne "${anonymous_index}" ]]; then
      jj bookmark create "c${i}" -r @ >/dev/null
    fi
    # Sleep 1s between chain tip commits so committer timestamps strictly
    # increase from c1..cN (committer.timestamp() resolution is 1s).
    sleep 1
  done

  # Build the multi-parent [merge] and [wip] on top using the captured
  # change-ids (anonymous parents have no bookmark to name).
  jj new "${parent_revs[@]}" -m "join 1: test diamond" >/dev/null
  jj new -m "wip" >/dev/null
}

# Build a single-parent (degenerate, not a join) chain so precondition 17 trips.
scenario_setup_single_parent() {
  local tmpdir
  tmpdir=$(mktemp -d -t jj-join-chains-test.XXXXXX)
  echo "${tmpdir}"
  cd "${tmpdir}"

  jj git init >/dev/null 2>&1
  echo "base" > base.txt
  jj describe -m "init" >/dev/null
  jj bookmark create main -r @ >/dev/null
  jj new -m "wip" >/dev/null
}

run_scenario_no_jj_repo() {
  local result
  result=$(
    set +e
    tmp=$(mktemp -d -t jj-join-chains-test.XXXXXX)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL no-jj-repo: cd to tmpdir failed"; exit 0; }
    reset_globals
    (precondition_checks) >/dev/null 2>&1
    code=$?
    if [[ $code -eq 10 ]]; then
      echo "PASS no-jj-repo"
    else
      echo "FAIL no-jj-repo: expected exit 10, got ${code}"
    fi
  )
  echo "${result}"
}

run_scenario_single_parent_fails() {
  local result
  result=$(
    set +e
    tmp=$(scenario_setup_single_parent)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL single-parent-fails: cd to tmpdir failed"; exit 0; }
    reset_globals
    (precondition_checks) >/dev/null 2>&1
    code=$?
    if [[ $code -eq 17 ]]; then
      echo "PASS single-parent-fails"
    else
      echo "FAIL single-parent-fails: expected exit 17, got ${code}"
    fi
  )
  echo "${result}"
}

run_scenario_two_chain_desc() {
  local result
  result=$(
    set +e
    tmp=$(scenario_setup_diamond 2 0)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL two-chain-desc: cd to tmpdir failed"; exit 0; }
    reset_globals
    precondition_checks
    out=$(print_chains)
    # Expect 2 lines, first containing c2 (later timestamp), second c1.
    line_count=$(printf '%s\n' "${out}" | sed '/^$/d' | wc -l | tr -d ' ')
    if [[ "${line_count}" -ne 2 ]]; then
      echo "FAIL two-chain-desc: expected 2 lines, got ${line_count}"
      echo "--- output ---"; echo "${out}"; echo "--- end ---"
      exit 0
    fi
    first_line=$(printf '%s\n' "${out}" | sed -n '1p')
    second_line=$(printf '%s\n' "${out}" | sed -n '2p')
    if ! grep -q 'c2' <<<"${first_line}"; then
      echo "FAIL two-chain-desc: first row should contain c2, got: ${first_line}"
      exit 0
    fi
    if ! grep -q 'c1' <<<"${second_line}"; then
      echo "FAIL two-chain-desc: second row should contain c1, got: ${second_line}"
      exit 0
    fi
    echo "PASS two-chain-desc"
  )
  echo "${result}"
}

run_scenario_two_chain_asc() {
  local result
  result=$(
    set +e
    tmp=$(scenario_setup_diamond 2 0)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL two-chain-asc: cd to tmpdir failed"; exit 0; }
    reset_globals
    order_dir="asc"
    precondition_checks
    out=$(print_chains)
    first_line=$(printf '%s\n' "${out}" | sed -n '1p')
    second_line=$(printf '%s\n' "${out}" | sed -n '2p')
    if ! grep -q 'c1' <<<"${first_line}"; then
      echo "FAIL two-chain-asc: first row should contain c1, got: ${first_line}"
      exit 0
    fi
    if ! grep -q 'c2' <<<"${second_line}"; then
      echo "FAIL two-chain-asc: second row should contain c2, got: ${second_line}"
      exit 0
    fi
    echo "PASS two-chain-asc"
  )
  echo "${result}"
}

run_scenario_anonymous_parent() {
  local result
  result=$(
    set +e
    # 2-chain diamond with chain 2 having no bookmark (anonymous).
    tmp=$(scenario_setup_diamond 2 2)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL anonymous-parent: cd to tmpdir failed"; exit 0; }
    reset_globals
    precondition_checks
    out=$(print_chains)
    # Anonymous parent row should have "(<short-id>)" in the bookmark column.
    if ! grep -qE '\([a-z]+\)' <<<"${out}"; then
      echo "FAIL anonymous-parent: expected anonymous '(<short-id>)' marker in output"
      echo "--- output ---"; echo "${out}"; echo "--- end ---"
      exit 0
    fi
    echo "PASS anonymous-parent"
  )
  echo "${result}"
}

run_scenario_limit() {
  local result
  result=$(
    set +e
    tmp=$(scenario_setup_diamond 3 0)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL limit: cd to tmpdir failed"; exit 0; }
    reset_globals
    limit="2"
    precondition_checks
    out=$(print_chains)
    line_count=$(printf '%s\n' "${out}" | sed '/^$/d' | wc -l | tr -d ' ')
    if [[ "${line_count}" -ne 2 ]]; then
      echo "FAIL limit: expected 2 lines, got ${line_count}"
      echo "--- output ---"; echo "${out}"; echo "--- end ---"
      exit 0
    fi
    echo "PASS limit"
  )
  echo "${result}"
}

run_scenario_tsv_format() {
  local result
  result=$(
    set +e
    tmp=$(scenario_setup_diamond 2 0)
    trap 'rm -rf "${tmp}"' EXIT
    cd "${tmp}" || { echo "FAIL tsv-format: cd to tmpdir failed"; exit 0; }
    reset_globals
    format="tsv"
    precondition_checks
    out=$(print_chains)
    # Each row should have exactly 3 tabs (4 fields).
    bad=0
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      tab_count=$(awk -F'\t' '{print NF-1}' <<<"${line}")
      if [[ "${tab_count}" -ne 3 ]]; then
        bad=$((bad+1))
        echo "FAIL tsv-format: line has ${tab_count} tabs (expected 3): ${line}"
      fi
    done <<<"${out}"
    if [[ "${bad}" -eq 0 ]]; then
      echo "PASS tsv-format"
    fi
  )
  echo "${result}"
}

run_tests() {
  local scenario="${1:-}"
  local out=""
  case "${scenario}" in
    "" )
      out+=$(run_scenario_no_jj_repo); out+=$'\n'
      out+=$(run_scenario_single_parent_fails); out+=$'\n'
      out+=$(run_scenario_two_chain_desc); out+=$'\n'
      out+=$(run_scenario_two_chain_asc); out+=$'\n'
      out+=$(run_scenario_anonymous_parent); out+=$'\n'
      out+=$(run_scenario_limit); out+=$'\n'
      out+=$(run_scenario_tsv_format)
      ;;
    no-jj-repo) out=$(run_scenario_no_jj_repo) ;;
    single-parent-fails) out=$(run_scenario_single_parent_fails) ;;
    two-chain-desc) out=$(run_scenario_two_chain_desc) ;;
    two-chain-asc) out=$(run_scenario_two_chain_asc) ;;
    anonymous-parent) out=$(run_scenario_anonymous_parent) ;;
    limit) out=$(run_scenario_limit) ;;
    tsv-format) out=$(run_scenario_tsv_format) ;;
    *)
      echo "Error: unknown test scenario '${scenario}'." >&2
      echo "Valid scenarios: no-jj-repo, single-parent-fails, two-chain-desc, two-chain-asc, anonymous-parent, limit, tsv-format" >&2
      return 1
      ;;
  esac
  echo "${out}"
  if grep -q '^FAIL' <<<"${out}"; then
    return 1
  fi
  return 0
}

# -----------------------------------------------------------------------------
# Main dispatch
# -----------------------------------------------------------------------------

if "${test_mode}"; then
  run_tests "${test_scenario}"
  exit $?
fi

precondition_checks
print_chains
