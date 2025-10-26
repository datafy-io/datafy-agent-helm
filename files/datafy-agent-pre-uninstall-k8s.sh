install_curl() {
  if command -v curl >/dev/null 2>&1; then
    return 0
  fi
  
  echo "curl not found, attempting to install..."
  
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y curl
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache curl
  else
    echo "Error: Cannot install curl - no supported package manager found (apt-get or apk)" >&2
    exit 1
  fi
  
  if ! command -v curl >/dev/null 2>&1; then
    echo "Error: Failed to install curl" >&2
    exit 1
  fi
  
  echo "curl installed successfully"
}

run_pre_uninstall() {
  echo "Running pre-uninstall validation and cleanup..."
  
  if [ -z "${DATAFY_TOKEN_SECRET_NAME:-}" ] || [ -z "${DATAFY_TOKEN_SECRET_KEY:-}" ]; then
    echo "Error: DATAFY_TOKEN_SECRET_NAME or DATAFY_TOKEN_SECRET_KEY not set" >&2
    exit 1
  fi
  
  if [ -z "${K8S_NAMESPACE:-}" ]; then
    echo "Error: K8S_NAMESPACE not set" >&2
    exit 1
  fi
  
  TOKEN=$(kubectl get secret "${DATAFY_TOKEN_SECRET_NAME}" -n "${K8S_NAMESPACE}" -o jsonpath="{.data.${DATAFY_TOKEN_SECRET_KEY}}" 2>/dev/null | base64 -d)
  
  if [ -z "${TOKEN:-}" ]; then
    echo "Error: Failed to retrieve TOKEN from secret ${DATAFY_TOKEN_SECRET_NAME}" >&2
    exit 1
  fi
  
  if [ -z "${CHANNEL:-}" ]; then
    echo "Error: CHANNEL not set" >&2
    exit 1
  fi
  
  case "$CHANNEL" in
    production)
      PRE_UNINSTALL_URL="https://agent.datafy.io/pre-uninstall-k8s"
      ENVIRONMENT="production"
      ;;
    staging)
      PRE_UNINSTALL_URL="https://agent-stg.datafy.io/pre-uninstall-k8s"
      ENVIRONMENT="staging"
      ;;
    development*)
      PRE_UNINSTALL_URL="https://agent-dev.datafy.io/pre-uninstall-k8s"
      ENVIRONMENT="development"
      ;;
    *)
      echo "Error: Unknown CHANNEL value: ${CHANNEL}" >&2
      exit 1
      ;;
  esac
  
  install_curl
  
  SKIP_CONFIRMATION=true TOKEN="${TOKEN}" DATAFY_ENVIRONMENT="${ENVIRONMENT}" K8S_NAMESPACE="${K8S_NAMESPACE}" \
    curl -sSfL "${PRE_UNINSTALL_URL}" | sh
  
  echo "Pre-uninstall validation completed successfully"
}

run_pre_uninstall()