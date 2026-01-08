#!/bin/bash
set -e

# Datafy Agent Helm Chart Uninstall Script
# Uninstalls datafy-agent helm release

# Default values
NAMESPACE="datafy-agent"
RELEASE_NAME="datafy-agent"
DELETE_NAMESPACE="false"
WAIT_TIMEOUT="5m"

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

Uninstall Datafy Agent Helm Chart

OPTIONS:
    -n, --namespace NAMESPACE       Namespace (default: datafy-agent)
    -r, --release-name NAME         Release name (default: datafy-agent)
    -d, --delete-namespace          Delete namespace after uninstall
    --timeout DURATION              Wait timeout (default: 5m)
    -h, --help                      Show help

EXAMPLES:
    $0
    $0 --namespace my-ns
    $0 --delete-namespace
    $0 --release-name my-agent --namespace my-ns --delete-namespace

EOF
    exit 1
}

check_prerequisites() {
    if ! command -v helm &> /dev/null; then
        print_error "helm not found. Please install helm."
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

delete_namespace_if_requested() {
    if [ "$DELETE_NAMESPACE" = "true" ]; then
        if kubectl get namespace "$NAMESPACE" &> /dev/null; then
            print_info "Deleting namespace '$NAMESPACE'..."
            kubectl delete namespace "$NAMESPACE" --timeout="$WAIT_TIMEOUT"
            print_info "Namespace deleted."
        else
            print_warn "Namespace '$NAMESPACE' not found."
        fi
    fi
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace) NAMESPACE="$2"; shift 2 ;;
        -r|--release-name) RELEASE_NAME="$2"; shift 2 ;;
        -d|--delete-namespace) DELETE_NAMESPACE="true"; shift ;;
        --timeout) WAIT_TIMEOUT="$2"; shift 2 ;;
        -h|--help) usage ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Main
main() {
    print_info "Datafy Agent Helm Chart Uninstallation"
    print_info "======================================="
    echo ""
    
    check_prerequisites
    check_release_exists
    uninstall_chart
    delete_namespace_if_requested
    
    echo ""
    print_info "======================================="
    print_info "Uninstallation completed!"
}

main
