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
MODE="AutoScaler"
TOKEN=""
DSO_URL="wss://dso.datafy.io"
ENABLE_CSI_DRIVER="false"
WAIT_TIMEOUT="5m"
DRY_RUN="false"
ATOMIC="true"
CREATE_NAMESPACE="true"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

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
  DATAFY_MODE                   Mode: sensor or AutoScaler (default: ${MODE})
  DATAFY_DSO_URL                DSO URL (default: ${DSO_URL})
  DATAFY_ENABLE_CSI_DRIVER      true/false (default: ${ENABLE_CSI_DRIVER})
  DATAFY_TIMEOUT                Helm timeout (default: ${WAIT_TIMEOUT})
  DATAFY_DRY_RUN                true/false (default: ${DRY_RUN})
  DATAFY_ATOMIC                 true/false (default: ${ATOMIC})
  DATAFY_CREATE_NAMESPACE       true/false (default: ${CREATE_NAMESPACE})
  DATAFY_HELM_REPO_NAME         Helm repo name (default: ${HELM_REPO_NAME})
  DATAFY_HELM_REPO_URL          Helm repo url (default: ${HELM_REPO_URL})

Examples:
  DATAFY_TOKEN=YOUR_TOKEN $0
  DATAFY_TOKEN=YOUR_TOKEN DATAFY_NAMESPACE=my-ns DATAFY_MODE=sensor $0
  DATAFY_TOKEN=YOUR_TOKEN DATAFY_ENABLE_CSI_DRIVER=true $0
  DATAFY_TOKEN=YOUR_TOKEN DATAFY_DRY_RUN=true $0

EOF
    exit "$exit_code"
}

normalize_bool() {
    # normalize_bool <value> <var_name_for_errors>
    local v="${1:-}"
    local name="${2:-value}"
    case "${v,,}" in
        1|true|yes|y|on) echo "true" ;;
        0|false|no|n|off|"") echo "false" ;;
        *)
            print_error "Invalid boolean for ${name}: '${v}'. Use true/false."
            exit 1
            ;;
    esac
}

normalize_mode() {
    local v="${1:-}"
    case "${v,,}" in
        sensor) echo "sensor" ;;
        autoscaler|auto-scaler|auto_scaler) echo "AutoScaler" ;;
        *)
            print_error "Invalid DATAFY_MODE: '${v}'. Use 'sensor' or 'AutoScaler'."
            exit 1
            ;;
    esac
}

apply_env_overrides() {
    NAMESPACE="${DATAFY_NAMESPACE:-$NAMESPACE}"
    RELEASE_NAME="${DATAFY_RELEASE_NAME:-$RELEASE_NAME}"
    CHART_VERSION="${DATAFY_CHART_VERSION:-$CHART_VERSION}"
    HELM_REPO_NAME="${DATAFY_HELM_REPO_NAME:-$HELM_REPO_NAME}"
    HELM_REPO_URL="${DATAFY_HELM_REPO_URL:-$HELM_REPO_URL}"

    MODE="$(normalize_mode "${DATAFY_MODE:-$MODE}")"
    TOKEN="${DATAFY_TOKEN:-$TOKEN}"
    DSO_URL="${DATAFY_DSO_URL:-$DSO_URL}"
    WAIT_TIMEOUT="${DATAFY_TIMEOUT:-$WAIT_TIMEOUT}"

    ENABLE_CSI_DRIVER="$(normalize_bool "${DATAFY_ENABLE_CSI_DRIVER:-$ENABLE_CSI_DRIVER}" "DATAFY_ENABLE_CSI_DRIVER")"
    DRY_RUN="$(normalize_bool "${DATAFY_DRY_RUN:-$DRY_RUN}" "DATAFY_DRY_RUN")"
    ATOMIC="$(normalize_bool "${DATAFY_ATOMIC:-$ATOMIC}" "DATAFY_ATOMIC")"
    CREATE_NAMESPACE="$(normalize_bool "${DATAFY_CREATE_NAMESPACE:-$CREATE_NAMESPACE}" "DATAFY_CREATE_NAMESPACE")"
}

check_prerequisites() {
    print_info "Checking prerequisites..."

    if ! command -v helm &> /dev/null; then
        print_error "helm not found. Install from: https://helm.sh/docs/intro/install/"
        exit 1
    fi

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl."
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

create_namespace_if_needed() {
    if [ "$CREATE_NAMESPACE" = "true" ]; then
        if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
            print_info "Creating namespace '$NAMESPACE'..."
            kubectl create namespace "$NAMESPACE"
        fi
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
    print_info "  Mode: $MODE"

    local cmd=(
        helm upgrade --install "$RELEASE_NAME" "${HELM_REPO_NAME}/datafy-agent"
        --version "$CHART_VERSION"
        --namespace "$NAMESPACE"
        --timeout "$WAIT_TIMEOUT"
        --set-string "agent.mode=$MODE"
        --set-string "agent.token=$TOKEN"
        --set-string "agent.dsoUrl=$DSO_URL"
        --set "awsEbsCsiDriver.enabled=$ENABLE_CSI_DRIVER"
    )

    [ "$CREATE_NAMESPACE" = "true" ] && cmd+=("--create-namespace")
    [ "$ATOMIC" = "true" ] && cmd+=("--atomic")

    if [ "$DRY_RUN" = "true" ]; then
        cmd+=("--dry-run" "--debug")
        print_warn "DRY RUN - No changes will be made"
    fi

    "${cmd[@]}"

    [ "$DRY_RUN" != "true" ] && print_info "Chart operation completed successfully!"
}

verify_installation() {
    [ "$DRY_RUN" = "true" ] && return

    print_info "Verifying installation..."
    echo ""
    helm status "$RELEASE_NAME" -n "$NAMESPACE"
    echo ""
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/instance="$RELEASE_NAME"
    echo ""
    print_info "To view logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -f"
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
    create_namespace_if_needed
    install_or_upgrade_chart
    verify_installation

    echo ""
    print_info "======================================"
    print_info "Installation completed!"
}

main "$@"
