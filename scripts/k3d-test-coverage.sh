#!/usr/bin/env bash
# Run chainsaw tests with coverage report showing tested vs deployed resources
#
# Usage: ./scripts/k3d-test-coverage.sh [--raw] [chainsaw args...]
#
# Options:
#   --raw    Show raw uncategorized output (original format)
#
# Environment:
#   CI, GITHUB_ACTIONS, NO_COLOR - Disable colors when set
#
# Exit codes:
#   0 - All tests passed
#   1 - Tests failed or error

set -euo pipefail

# Global flag for raw output mode
RAW_MODE=0

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

# Categorize a resource as application, foundation, or system
# Returns: "application", "foundation", or "system"
categorize_resource() {
    local key="$1"
    local kind="${key%%/*}"
    local rest="${key#*/}"
    local ns="${rest%%/*}"
    local name="${rest#*/}"

    # System components (k3s internals, Cilium internals, auto-generated)
    # These are excluded from coverage calculation because they are:
    # - Not managed by our nixidy/ArgoCD stack
    # - Auto-created by k3s or other controllers
    # - Internal components of our foundation layer
    case "$key" in
        # k3s DNS - managed by k3s, not our stack
        Deployment/kube-system/coredns) echo "system"; return ;;
        # k3s storage provisioner - managed by k3s
        Deployment/kube-system/local-path-provisioner) echo "system"; return ;;
        # k3s metrics - managed by k3s
        Deployment/kube-system/metrics-server) echo "system"; return ;;
        # Cilium internal envoy proxy - managed by Cilium operator
        DaemonSet/kube-system/cilium-envoy) echo "system"; return ;;
        # Auto-generated by cert-manager gateway-shim from HTTPRoute annotation
        # Duplicates our explicit step-ca-tls Certificate
        Certificate/gateway-system/test-cert-tls) echo "system"; return ;;
    esac

    # k3s servicelb auto-created DaemonSets (svclb-*)
    # These are auto-created by k3s for LoadBalancer services
    if [[ "$kind" == "DaemonSet" && "$ns" == "kube-system" && "$name" == svclb-* ]]; then
        echo "system"
        return
    fi

    # Foundation resources (CNI layer we deploy but is infrastructure)
    case "$key" in
        DaemonSet/kube-system/cilium) echo "foundation"; return ;;
        Deployment/kube-system/cilium-operator) echo "foundation"; return ;;
    esac

    # Application resources (our nixidy/ArgoCD managed stack)
    # Includes: argocd, cert-manager, sops-secrets-operator, step-ca,
    # gateway-system, plus Gateway API resources
    echo "application"
}

# Get human-readable description for system components
get_system_description() {
    local key="$1"
    local kind="${key%%/*}"
    local rest="${key#*/}"
    local ns="${rest%%/*}"
    local name="${rest#*/}"

    case "$key" in
        Deployment/kube-system/coredns) echo "k3s DNS" ;;
        Deployment/kube-system/local-path-provisioner) echo "k3s storage" ;;
        Deployment/kube-system/metrics-server) echo "k3s metrics" ;;
        DaemonSet/kube-system/cilium-envoy) echo "Cilium internal" ;;
        Certificate/gateway-system/test-cert-tls) echo "gateway-shim duplicate" ;;
        DaemonSet/kube-system/svclb-*) echo "k3s servicelb auto-created" ;;
        *) echo "system component" ;;
    esac
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

    # Categorize resources and calculate coverage
    local matched=0
    local untested=()
    local key category

    # Categorized counts
    local app_total=0 app_tested=0
    local foundation_total=0 foundation_tested=0
    local system_total=0 system_tested=0
    local system_resources=()

    for key in "${!deployed_resources[@]}"; do
        category=$(categorize_resource "$key")

        case "$category" in
            application)
                (( app_total++ )) || true
                if [[ -n "${tested_resources[$key]:-}" ]]; then
                    (( app_tested++ )) || true
                    (( matched++ )) || true
                else
                    untested+=("$key")
                fi
                ;;
            foundation)
                (( foundation_total++ )) || true
                if [[ -n "${tested_resources[$key]:-}" ]]; then
                    (( foundation_tested++ )) || true
                    (( matched++ )) || true
                else
                    untested+=("$key")
                fi
                ;;
            system)
                (( system_total++ )) || true
                system_resources+=("$key")
                if [[ -n "${tested_resources[$key]:-}" ]]; then
                    (( system_tested++ )) || true
                    (( matched++ )) || true
                fi
                ;;
        esac
    done

    # Calculate raw coverage (all resources)
    local raw_coverage=0
    if [[ $deployed_count -gt 0 ]]; then
        raw_coverage=$(( matched * 100 / deployed_count ))
    fi

    # Calculate managed coverage (excluding system components)
    local managed_total=$(( app_total + foundation_total ))
    local managed_tested=$(( app_tested + foundation_tested ))
    local managed_coverage=0
    if [[ $managed_total -gt 0 ]]; then
        managed_coverage=$(( managed_tested * 100 / managed_total ))
    fi

    if [[ $RAW_MODE -eq 1 ]]; then
        # Original raw output format
        local cov_color="$RED"
        if [[ $raw_coverage -ge 80 ]]; then
            cov_color="$GREEN"
        elif [[ $raw_coverage -ge 50 ]]; then
            cov_color="$YELLOW"
        fi

        echo ""
        echo "  Resource instance coverage: ${cov_color}${BOLD}${raw_coverage}%${RESET} (${matched}/${deployed_count})"
        echo ""

        if [[ ${#untested[@]} -gt 0 ]] || [[ ${#system_resources[@]} -gt 0 ]]; then
            echo "${BOLD}Untested Resources:${RESET}"
            local rest ns name
            # Combine untested managed resources with untested system resources
            local all_untested=()
            for key in "${untested[@]}"; do
                all_untested+=("$key")
            done
            for key in "${system_resources[@]}"; do
                if [[ -z "${tested_resources[$key]:-}" ]]; then
                    all_untested+=("$key")
                fi
            done
            for key in "${all_untested[@]}"; do
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
    else
        # Categorized output format
        echo ""
        echo "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
        echo "${BOLD}                        COVERAGE BY CATEGORY                        ${RESET}"
        echo "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
        echo ""

        # Application coverage
        local app_cov_pct=0
        if [[ $app_total -gt 0 ]]; then
            app_cov_pct=$(( app_tested * 100 / app_total ))
        fi
        local app_color="$RED"
        [[ $app_cov_pct -ge 80 ]] && app_color="$GREEN"
        [[ $app_cov_pct -ge 50 && $app_cov_pct -lt 80 ]] && app_color="$YELLOW"
        printf "  Application Resources:    ${app_color}%2d/%2d  (%3d%%)${RESET}\n" "$app_tested" "$app_total" "$app_cov_pct"

        # Foundation coverage
        local fnd_cov_pct=0
        if [[ $foundation_total -gt 0 ]]; then
            fnd_cov_pct=$(( foundation_tested * 100 / foundation_total ))
        fi
        local fnd_color="$RED"
        [[ $fnd_cov_pct -ge 80 ]] && fnd_color="$GREEN"
        [[ $fnd_cov_pct -ge 50 && $fnd_cov_pct -lt 80 ]] && fnd_color="$YELLOW"
        printf "  Foundation Resources:     ${fnd_color}%2d/%2d  (%3d%%)${RESET}\n" "$foundation_tested" "$foundation_total" "$fnd_cov_pct"

        echo "  ${DIM}─────────────────────────────────────────────────────────────────${RESET}"

        # Managed total
        local mgd_color="$RED"
        [[ $managed_coverage -ge 80 ]] && mgd_color="$GREEN"
        [[ $managed_coverage -ge 50 && $managed_coverage -lt 80 ]] && mgd_color="$YELLOW"
        printf "  ${BOLD}Managed Resources Total:  ${mgd_color}%2d/%2d  (%3d%%)${RESET}\n" "$managed_tested" "$managed_total" "$managed_coverage"

        # Untested managed resources
        if [[ ${#untested[@]} -gt 0 ]]; then
            echo ""
            echo "${BOLD}Untested Managed Resources:${RESET}"
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
        fi

        # System components section
        echo ""
        echo "${BOLD}System Components (excluded from coverage):${RESET}"
        local rest ns name desc
        for key in "${system_resources[@]}"; do
            kind="${key%%/*}"
            rest="${key#*/}"
            ns="${rest%%/*}"
            name="${rest#*/}"
            desc=$(get_system_description "$key")
            printf "  ${DIM}○${RESET} ${DIM}%-15s${RESET} %s ${DIM}(%s)${RESET} - ${DIM}%s${RESET}\n" "$kind" "$name" "$ns" "$desc"
        done | sort

        echo ""
        printf "  ${DIM}Raw Resource Count:       %2d/%2d  (%3d%%)${RESET}\n" "$matched" "$deployed_count" "$raw_coverage"
    fi

    echo ""
    echo "${BOLD}═══════════════════════════════════════════════════════════════════${RESET}"
}

main() {
    setup_colors

    # Parse --raw flag
    local args=()
    for arg in "$@"; do
        if [[ "$arg" == "--raw" ]]; then
            RAW_MODE=1
        else
            args+=("$arg")
        fi
    done

    local report_dir
    report_dir=$(mktemp -d)
    trap 'rm -rf "$report_dir"' EXIT

    local test_failed=0
    if ! run_chainsaw_tests "$report_dir" "${args[@]}"; then
        test_failed=1
    fi

    print_test_summary "$report_dir/chainsaw-report.xml"
    print_coverage_report "kubernetes/tests/local-k3d"

    exit $test_failed
}

main "$@"
