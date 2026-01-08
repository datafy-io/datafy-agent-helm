#!/bin/bash
set -e

# Datafy Agent Helm Chart Installation Script
# Installs or upgrades datafy-agent from the official helm repository

# Default values
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
    cat << EOF
Usage: $0 [OPTIONS]

Install or upgrade Datafy Agent Helm Chart from repository

OPTIONS:
    -t, --token TOKEN               Required: Datafy agent token
    -n, --namespace NAMESPACE       Namespace (default: datafy-agent)
    -r, --release-name NAME         Release name (default: datafy-agent)
    -v, --chart-version VERSION     Chart version (default: 2.0.2)
    -m, --mode MODE                 Mode: sensor or AutoScaler (default: AutoScaler)
    -u, --dso-url URL               DSO URL (default: wss://dso.datafy.io)
    -c, --enable-csi-driver         Enable AWS EBS CSI driver
    --timeout DURATION              Wait timeout (default: 5m)
    --dry-run                       Simulate installation
    --no-atomic                     Disable atomic installation
    --no-create-namespace           Don't auto-create namespace
    -h, --help                      Show help

EXAMPLES:
    $0 --token YOUR_TOKEN
    $0 --token YOUR_TOKEN --namespace my-ns --mode sensor
    $0 --token YOUR_TOKEN --enable-csi-driver
    $0 --token YOUR_TOKEN --dry-run

EOF
    exit 1
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
        print_error "Token required. Use -t or --token"
        usage
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
    
    local cmd="helm upgrade --install $RELEASE_NAME ${HELM_REPO_NAME}/datafy-agent"
    cmd="$cmd --version $CHART_VERSION"
    cmd="$cmd --namespace $NAMESPACE"
    cmd="$cmd --timeout $WAIT_TIMEOUT"
    cmd="$cmd --set agent.mode=$MODE"
    cmd="$cmd --set agent.token=$TOKEN"
    cmd="$cmd --set agent.dsoUrl=$DSO_URL"
    cmd="$cmd --set awsEbsCsiDriver.enabled=$ENABLE_CSI_DRIVER"
    
    [ "$CREATE_NAMESPACE" = "true" ] && cmd="$cmd --create-namespace"
    [ "$ATOMIC" = "true" ] && cmd="$cmd --atomic"
    
    if [ "$DRY_RUN" = "true" ]; then
        cmd="$cmd --dry-run --debug"
        print_warn "DRY RUN - No changes will be made"
    fi
    
    eval "$cmd"
    
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

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--token) TOKEN="$2"; shift 2 ;;
        -n|--namespace) NAMESPACE="$2"; shift 2 ;;
        -r|--release-name) RELEASE_NAME="$2"; shift 2 ;;
        -v|--chart-version) CHART_VERSION="$2"; shift 2 ;;
        -m|--mode) MODE="$2"; shift 2 ;;
        -u|--dso-url) DSO_URL="$2"; shift 2 ;;
        -c|--enable-csi-driver) ENABLE_CSI_DRIVER="true"; shift ;;
        --timeout) WAIT_TIMEOUT="$2"; shift 2 ;;
        --dry-run) DRY_RUN="true"; shift ;;
        --no-atomic) ATOMIC="false"; shift ;;
        --no-create-namespace) CREATE_NAMESPACE="false"; shift ;;
        -h|--help) usage ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

main() {
    print_info "Datafy Agent Helm Chart Installation"
    print_info "======================================"
    echo ""
    
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

main
