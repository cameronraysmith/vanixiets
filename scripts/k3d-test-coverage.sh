#!/usr/bin/env bash
# Run chainsaw tests with coverage report showing tested vs deployed resources
#
# Usage: ./scripts/k3d-test-coverage.sh [chainsaw args...]
#
# Environment:
#   CI, GITHUB_ACTIONS, NO_COLOR - Disable colors when set
#
# Exit codes:
#   0 - All tests passed
#   1 - Tests failed or error

set -euo pipefail

# shellcheck disable=SC2034  # Colors are used via variable expansion
setup_colors() {
    if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${NO_COLOR:-}" ]]; then
        RED="" GREEN="" YELLOW="" BOLD="" DIM="" RESET=""
    else
        RED=$'\e[31m' GREEN=$'\e[32m' YELLOW=$'\e[33m'
        BOLD=$'\e[1m' DIM=$'\e[2m' RESET=$'\e[0m'
    fi
}

run_chainsaw_tests() {
    local report_dir="$1"
    shift

    echo "${BOLD}Running chainsaw tests...${RESET}"
    echo ""

    if chainsaw test kubernetes/tests/local-k3d/ "$@" \
        --report-format JUNIT-OPERATION \
        --report-path "$report_dir" 2>&1; then
        return 0
    else
        return 1
    fi
}

print_test_summary() {
    local report_file="$1"

    echo ""
    echo "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}                        TEST SUMMARY                               ${RESET}"
    echo "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
    echo ""

    if [[ ! -f "$report_file" ]]; then
        echo "  ${YELLOW}Warning: No test report found${RESET}"
        return
    fi

    local total_ops total_time
    total_ops=$(xmllint --xpath 'string(/testsuites/@tests)' "$report_file" 2>/dev/null || echo "0")
    total_time=$(xmllint --xpath 'string(/testsuites/@time)' "$report_file" 2>/dev/null || echo "0")

    echo "${BOLD}Test Execution:${RESET}"
    echo "  Total operations: ${GREEN}${total_ops}${RESET}"
    echo "  Total time: ${DIM}${total_time}s${RESET}"
    echo ""

    echo "${BOLD}By Test Suite:${RESET}"
    local suite suite_tests suite_failures suite_time status
    for suite in foundation infrastructure local-k3d; do
        suite_tests=$(xmllint --xpath "string(//testsuite[@name='$suite']/@tests)" "$report_file" 2>/dev/null || echo "0")
        suite_failures=$(xmllint --xpath "string(//testsuite[@name='$suite']/@failures)" "$report_file" 2>/dev/null || echo "0")
        suite_time=$(xmllint --xpath "string(//testsuite[@name='$suite']/@time)" "$report_file" 2>/dev/null || echo "0")

        if [[ "$suite_tests" != "0" ]]; then
            if [[ "$suite_failures" == "0" ]]; then
                status="${GREEN}PASS${RESET}"
            else
                status="${RED}FAIL${RESET}"
            fi
            printf "  %-20s %s  %3s ops  ${DIM}%ss${RESET}\n" "$suite" "$status" "$suite_tests" "$suite_time"
        fi
    done
}

collect_deployed_resources() {
    local -n deployed_ref=$1
    local -n type_counts_ref=$2

    # Workloads (Deployment, StatefulSet, DaemonSet)
    local line ns name kind key
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ns=$(awk '{print $1}' <<< "$line")
        name=$(awk '{print $2}' <<< "$line")
        kind=$(awk '{print $3}' <<< "$line")
        key="${kind}/${ns}/${name}"
        deployed_ref["$key"]=1
    done < <(kubectl get deploy,sts,ds -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,KIND:.kind' --no-headers 2>/dev/null | grep -v '^$')

    # Gateway API resources
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ns=$(awk '{print $1}' <<< "$line")
        name=$(awk '{print $2}' <<< "$line")
        deployed_ref["Gateway/${ns}/${name}"]=1
    done < <(kubectl get gateway -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name' --no-headers 2>/dev/null | grep -v '^$')

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ns=$(awk '{print $1}' <<< "$line")
        name=$(awk '{print $2}' <<< "$line")
        deployed_ref["HTTPRoute/${ns}/${name}"]=1
    done < <(kubectl get httproute -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name' --no-headers 2>/dev/null | grep -v '^$')

    # Certificates
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ns=$(awk '{print $1}' <<< "$line")
        name=$(awk '{print $2}' <<< "$line")
        deployed_ref["Certificate/${ns}/${name}"]=1
    done < <(kubectl get certificate -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name' --no-headers 2>/dev/null | grep -v '^$')

    # ClusterIssuers (cluster-scoped)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        deployed_ref["ClusterIssuer/-/${line}"]=1
    done < <(kubectl get clusterissuer -o custom-columns='NAME:.metadata.name' --no-headers 2>/dev/null | grep -v '^$')

    # Count by type
    for key in "${!deployed_ref[@]}"; do
        kind="${key%%/*}"
        type_counts_ref["$kind"]=$(( ${type_counts_ref["$kind"]:-0} + 1 ))
    done
}

collect_tested_resources() {
    local -n tested_ref=$1
    # shellcheck disable=SC2178  # nameref to associative array
    local -n type_counts_ref=$2
    local test_dir="$3"

    local file current_kind current_name current_ns line key

    while IFS= read -r file; do
        current_kind=""
        current_name=""
        current_ns="-"

        while IFS= read -r line; do
            # New document resets state
            if [[ "$line" == "---" ]]; then
                if [[ -n "$current_kind" && -n "$current_name" ]]; then
                    key="${current_kind}/${current_ns}/${current_name}"
                    tested_ref["$key"]=1
                fi
                current_kind=""
                current_name=""
                current_ns="-"
                continue
            fi

            # Extract kind
            if [[ "$line" =~ ^kind:\ *(.+)$ ]]; then
                current_kind="${BASH_REMATCH[1]}"
            fi

            # Extract name (first name field is metadata.name)
            if [[ "$line" =~ ^[[:space:]]+name:\ *(.+)$ ]]; then
                if [[ -z "$current_name" ]]; then
                    current_name="${BASH_REMATCH[1]}"
                fi
            fi

            # Extract namespace
            if [[ "$line" =~ ^[[:space:]]+namespace:\ *(.+)$ ]]; then
                current_ns="${BASH_REMATCH[1]}"
            fi
        done < "$file"

        # Last resource in file
        if [[ -n "$current_kind" && -n "$current_name" ]]; then
            key="${current_kind}/${current_ns}/${current_name}"
            tested_ref["$key"]=1
        fi
    done < <(find "$test_dir" -name "*assert*.yaml" -type f)

    # Count by type
    for key in "${!tested_ref[@]}"; do
        kind="${key%%/*}"
        type_counts_ref["$kind"]=$(( ${type_counts_ref["$kind"]:-0} + 1 ))
    done
}

print_resource_table() {
    local -n counts_ref=$1
    local total=$2

    local kind count
    for kind in Deployment StatefulSet DaemonSet Gateway HTTPRoute Certificate ClusterIssuer; do
        count="${counts_ref[$kind]:-0}"
        if [[ "$count" -gt 0 ]]; then
            printf "  %-15s %3d\n" "$kind" "$count"
        fi
    done
    echo "  ${DIM}─────────────────────${RESET}"
    printf "  %-15s %3d\n" "Total" "$total"
}

print_coverage_report() {
    local test_dir="$1"

    echo ""
    echo "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}                     RESOURCE COVERAGE                             ${RESET}"
    echo "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
    echo ""

    declare -A deployed_resources
    # shellcheck disable=SC2034  # passed to function via nameref
    declare -A deployed_type_counts
    declare -A tested_resources
    # shellcheck disable=SC2034  # passed to function via nameref
    declare -A tested_type_counts

    collect_deployed_resources deployed_resources deployed_type_counts
    collect_tested_resources tested_resources tested_type_counts "$test_dir"

    local deployed_count=${#deployed_resources[@]}
    local tested_count=${#tested_resources[@]}

    echo "${BOLD}Deployed Resources:${RESET}"
    print_resource_table deployed_type_counts "$deployed_count"

    echo ""
    echo "${BOLD}Tested Resources:${RESET}"
    print_resource_table tested_type_counts "$tested_count"

    echo ""
    echo "${BOLD}Coverage Analysis:${RESET}"

    # Calculate coverage
    local matched=0
    local untested=()
    local key

    for key in "${!deployed_resources[@]}"; do
        if [[ -n "${tested_resources[$key]:-}" ]]; then
            (( matched++ )) || true
        else
            untested+=("$key")
        fi
    done

    local coverage=0
    if [[ $deployed_count -gt 0 ]]; then
        coverage=$(( matched * 100 / deployed_count ))
    fi

    # Color-code coverage
    local cov_color="$RED"
    if [[ $coverage -ge 80 ]]; then
        cov_color="$GREEN"
    elif [[ $coverage -ge 50 ]]; then
        cov_color="$YELLOW"
    fi

    echo ""
    echo "  Resource instance coverage: ${cov_color}${BOLD}${coverage}%${RESET} (${matched}/${deployed_count})"
    echo ""

    if [[ ${#untested[@]} -gt 0 ]]; then
        echo "${BOLD}Untested Resources:${RESET}"
        local rest ns name
        for key in "${untested[@]}"; do
            kind="${key%%/*}"
            rest="${key#*/}"
            ns="${rest%%/*}"
            name="${rest#*/}"
            if [[ "$ns" == "-" ]]; then
                printf "  ${YELLOW}○${RESET} ${DIM}%-15s${RESET} %s\n" "$kind" "$name"
            else
                printf "  ${YELLOW}○${RESET} ${DIM}%-15s${RESET} %s ${DIM}(%s)${RESET}\n" "$kind" "$name" "$ns"
            fi
        done | sort
    else
        echo "  ${GREEN}All deployed resources have test coverage${RESET}"
    fi

    echo ""
    echo "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
}

main() {
    setup_colors

    local report_dir
    report_dir=$(mktemp -d)
    trap 'rm -rf "$report_dir"' EXIT

    local test_failed=0
    if ! run_chainsaw_tests "$report_dir" "$@"; then
        test_failed=1
    fi

    print_test_summary "$report_dir/chainsaw-report.xml"
    print_coverage_report "kubernetes/tests/local-k3d"

    exit $test_failed
}

main "$@"
