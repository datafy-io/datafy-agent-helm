#!/bin/bash
set -euo pipefail

# Datafy Agent Helm Chart Installation Script (env-driven)
# Installs or upgrades datafy-agent from the official helm repository

# Defaults (override via environment variables documented in usage())
NAMESPACE="datafy-agent"
RELEASE_NAME="datafy-agent"
CHART_VERSION="2.0.2"
HELM_REPO_NAME="datafyio"
HELM_REPO_URL="https://helm.datafy.io/datafy-agent"
TOKEN=""
DSO_URL=""
WAIT_TIMEOUT="5m"
DRY_RUN="false"
DEBUG="false"
ATOMIC="true"
ADDITIONAL_HELM=""

print_info() { echo "[INFO] $1"; }
print_warn() { echo "[WARN] $1"; }
print_error() { echo "[ERROR] $1"; }

usage() {
    local exit_code="${1:-0}"
    cat << EOF
Usage:
  DATAFY_TOKEN=... $0

This script is configured via environment variables (friendly for curl | bash).

Required:
  DATAFY_TOKEN                  Datafy agent token

Optional (defaults shown):
  DATAFY_NAMESPACE              Kubernetes namespace (default: ${NAMESPACE})
  DATAFY_RELEASE_NAME           Helm release name (default: ${RELEASE_NAME})
  DATAFY_CHART_VERSION          Chart version (default: ${CHART_VERSION})
  DATAFY_DSO_URL                DSO URL (optional)
  DATAFY_TIMEOUT                Helm timeout (default: ${WAIT_TIMEOUT})
  DATAFY_DRY_RUN                true/false (default: ${DRY_RUN})
  DATAFY_DEBUG                  true/false - Enable helm debug output (default: ${DEBUG})
  DATAFY_ATOMIC                 true/false (default: ${ATOMIC})
  DATAFY_HELM_REPO_NAME         Helm repo name (default: ${HELM_REPO_NAME})
  DATAFY_HELM_REPO_URL          Helm repo url (default: ${HELM_REPO_URL})
  DATAFY_ADDITIONAL_HELM        Additional helm values as comma-separated key=value pairs
                                 Example: "agent.dsoUrl=test,agent.mode=AutoScaler"

Examples:
  DATAFY_TOKEN=YOUR_TOKEN $0
  DATAFY_TOKEN=YOUR_TOKEN DATAFY_DRY_RUN=true $0
  DATAFY_TOKEN=YOUR_TOKEN DATAFY_ADDITIONAL_HELM="agent.mode=AutoScaler" $0
  DATAFY_TOKEN=YOUR_TOKEN DATAFY_ADDITIONAL_HELM="agent.mode=sensor,agent.dsoUrl=wss://custom.dso.url" $0
  # Note: Complex values like affinity require using helm values files or --set-file

EOF
    exit "$exit_code"
}

is_truthy() {
    # is_truthy <value> - returns 0 (true) if value is truthy, 1 (false) otherwise
    local v="${1:-}"
    case "${v,,}" in
        1|true|yes|y|on) return 0 ;;
        *) return 1 ;;
    esac
}

apply_env_overrides() {
    NAMESPACE="${DATAFY_NAMESPACE:-$NAMESPACE}"
    RELEASE_NAME="${DATAFY_RELEASE_NAME:-$RELEASE_NAME}"
    CHART_VERSION="${DATAFY_CHART_VERSION:-$CHART_VERSION}"
    HELM_REPO_NAME="${DATAFY_HELM_REPO_NAME:-$HELM_REPO_NAME}"
    HELM_REPO_URL="${DATAFY_HELM_REPO_URL:-$HELM_REPO_URL}"

    TOKEN="${DATAFY_TOKEN:-$TOKEN}"
    DSO_URL="${DATAFY_DSO_URL:-$DSO_URL}"
    WAIT_TIMEOUT="${DATAFY_TIMEOUT:-$WAIT_TIMEOUT}"

    if is_truthy "${DATAFY_DRY_RUN:-$DRY_RUN}"; then
        DRY_RUN="true"
    else
        DRY_RUN="false"
    fi

    if is_truthy "${DATAFY_DEBUG:-$DEBUG}"; then
        DEBUG="true"
    else
        DEBUG="false"
    fi

    if is_truthy "${DATAFY_ATOMIC:-$ATOMIC}"; then
        ATOMIC="true"
    else
        ATOMIC="false"
    fi

    ADDITIONAL_HELM="${DATAFY_ADDITIONAL_HELM:-$ADDITIONAL_HELM}"
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

setup_helm_repo() {
    print_info "Setting up Helm repository..."

    if helm repo list 2>/dev/null | grep -q "^${HELM_REPO_NAME}"; then
        print_info "Repo '${HELM_REPO_NAME}' exists, updating..."
    else
        print_info "Adding repo '${HELM_REPO_NAME}'..."
        helm repo add "${HELM_REPO_NAME}" "${HELM_REPO_URL}"
    fi

    helm repo update &> /dev/null
    print_info "Helm repository ready"
}

validate_token() {
    if [ -z "$TOKEN" ]; then
        print_error "DATAFY_TOKEN is required."
        usage 1
    fi
}

install_or_upgrade_chart() {
    if helm status "$RELEASE_NAME" -n "$NAMESPACE" &> /dev/null; then
        print_info "Release exists, upgrading Datafy Agent..."
    else
        print_info "Installing Datafy Agent..."
    fi

    print_info "  Release: $RELEASE_NAME"
    print_info "  Namespace: $NAMESPACE"
    print_info "  Version: $CHART_VERSION"

    local cmd=(
        helm upgrade --install "$RELEASE_NAME" "${HELM_REPO_NAME}/datafy-agent"
        --version "$CHART_VERSION"
        --namespace "$NAMESPACE"
        --timeout "$WAIT_TIMEOUT"
        --create-namespace
        --set-string "agent.token=$TOKEN"
    )

    [ -n "$DSO_URL" ] && cmd+=("--set-string" "agent.dsoUrl=$DSO_URL")

    # Add additional helm values if provided
    if [ -n "$ADDITIONAL_HELM" ]; then
        local old_ifs="$IFS"
        IFS=','
        for value in $ADDITIONAL_HELM; do
            IFS="$old_ifs"
            # Trim whitespace
            value=$(echo "$value" | xargs)
            if [[ "$value" == *"="* ]]; then
                cmd+=("--set-string" "$value")
            fi
            IFS=','
        done
        IFS="$old_ifs"
    fi

    [ "$ATOMIC" = "true" ] && cmd+=("--atomic")
    [ "$DEBUG" = "true" ] && cmd+=("--debug")

    if [ "$DRY_RUN" = "true" ]; then
        cmd+=("--dry-run" "--debug")
        print_warn "DRY RUN - No changes will be made"
    fi

    "${cmd[@]}"

    [ "$DRY_RUN" != "true" ] && print_info "Chart operation completed successfully!"
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

    print_info "Datafy Agent Helm Chart Installation (env-driven)"
    print_info "======================================"
    echo ""

    apply_env_overrides

    validate_token
    check_prerequisites
    setup_helm_repo
    install_or_upgrade_chart

    echo ""
    print_info "======================================"
    print_info "Installation completed!"
}

main "$@"
