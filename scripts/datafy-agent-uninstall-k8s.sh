#!/bin/bash
set -euo pipefail

# Datafy Agent Helm Chart Uninstall Script (env-driven)
# Uninstalls datafy-agent helm release

# Defaults (override via environment variables documented in usage())
NAMESPACE="datafy-agent"
RELEASE_NAME="datafy-agent"
WAIT_TIMEOUT="5m"

print_info() { echo "[INFO] $1"; }
print_warn() { echo "[WARN] $1"; }
print_error() { echo "[ERROR] $1"; }

usage() {
    local exit_code="${1:-0}"
    cat << EOF
Usage:
  $0

This script is configured via environment variables (friendly for curl | bash).

Optional (defaults shown):
  DATAFY_NAMESPACE              Kubernetes namespace (default: ${NAMESPACE})
  DATAFY_RELEASE_NAME           Helm release name (default: ${RELEASE_NAME})
  DATAFY_TIMEOUT                Helm timeout (default: ${WAIT_TIMEOUT})

Examples:
  $0
  DATAFY_NAMESPACE=my-ns $0
  DATAFY_RELEASE_NAME=my-agent DATAFY_NAMESPACE=my-ns $0

EOF
    exit "$exit_code"
}

apply_env_overrides() {
    NAMESPACE="${DATAFY_NAMESPACE:-$NAMESPACE}"
    RELEASE_NAME="${DATAFY_RELEASE_NAME:-$RELEASE_NAME}"
    WAIT_TIMEOUT="${DATAFY_TIMEOUT:-$WAIT_TIMEOUT}"
}

check_prerequisites() {
    print_info "Checking prerequisites..."

    if ! command -v helm &> /dev/null; then
        print_error "helm not found. Install from: https://helm.sh/docs/intro/install/"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to cluster. Check kubeconfig."
        exit 1
    fi

    print_info "Prerequisites OK"
}

check_release_exists() {
    if ! helm status "$RELEASE_NAME" -n "$NAMESPACE" &> /dev/null; then
        print_warn "Release '$RELEASE_NAME' not found in namespace '$NAMESPACE'"
        print_info "Nothing to uninstall."
        exit 0
    fi
}

uninstall_chart() {
    print_info "Uninstalling Datafy Agent..."
    print_info "  Release: $RELEASE_NAME"
    print_info "  Namespace: $NAMESPACE"

    helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE" --timeout "$WAIT_TIMEOUT"

    print_info "Helm release uninstalled successfully!"
}

main() {
    # Minimal help flag for discoverability; everything else is env-driven.
    if [[ $# -gt 0 ]]; then
        case "${1:-}" in
            -h|--help|help) usage 0 ;;
            *)
                print_error "This script is configured via environment variables (not CLI flags)."
                usage 1
                ;;
        esac
    fi

    print_info "Datafy Agent Helm Chart Uninstallation (env-driven)"
    print_info "======================================"
    echo ""

    apply_env_overrides
    check_prerequisites
    check_release_exists
    uninstall_chart

    echo ""
    print_info "======================================"
    print_info "Uninstallation completed!"
}

main "$@"
