#!/usr/bin/env bash
# Upgrade matrix check for Helm upgrades.
# Mirrors verify_upgrade_matrix() in datafy-agent-install.sh.
# Runs as a pre-upgrade Helm hook Job before any DaemonSet pods are updated.
#
# Required env vars:
#   TARGET_VERSION  - The version being deployed
#   AGENT_MODE      - autoscaler or sensor
#   DOWNLOAD_URL    - Base URL for the blacklist CSV
#   NAMESPACE       - Kubernetes namespace of the DaemonSet
#   DAEMONSET_NAME  - Name of the agent DaemonSet

set -euo pipefail

KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
KUBE_CA=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
KUBE_HOST="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"

# Fetch the current DaemonSet to read the deployed version label.
# This runs before any DaemonSet pods are updated, so the label still
# reflects the currently running version.
DS_JSON=$(curl -sSf \
  --cacert "${KUBE_CA}" \
  -H "Authorization: Bearer ${KUBE_TOKEN}" \
  "${KUBE_HOST}/apis/apps/v1/namespaces/${NAMESPACE}/daemonsets/${DAEMONSET_NAME}" 2>/dev/null) || {
  echo "WARNING: Could not fetch DaemonSet, skipping upgrade matrix check"
  exit 0
}

CURRENT_VERSION=$(printf '%s' "${DS_JSON}" | awk -F'"' '$2 == "app.agent.version" {print $4; exit}')

if [ -z "${CURRENT_VERSION:-}" ]; then
  echo "No current version label found on DaemonSet, skipping upgrade matrix check"
  exit 0
fi

echo "Upgrade matrix check: ${CURRENT_VERSION} -> ${TARGET_VERSION}"

if [ "${CURRENT_VERSION}" = "${TARGET_VERSION}" ]; then
  echo "ALLOWED: Current and target versions are identical"
  exit 0
fi

_is_semver() {
  printf '%s' "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'
}

if ! _is_semver "${CURRENT_VERSION}"; then
  echo "ALLOWED: Current version '${CURRENT_VERSION}' is a non-semver build"
  exit 0
fi

if ! _is_semver "${TARGET_VERSION}"; then
  echo "ALLOWED: Target version '${TARGET_VERSION}' is a non-semver build"
  exit 0
fi

CURRENT_MAJOR=$(printf '%s' "${CURRENT_VERSION}" | cut -d. -f1)
TARGET_MAJOR=$(printf '%s' "${TARGET_VERSION}" | cut -d. -f1)

if [ "${CURRENT_MAJOR}" != "${TARGET_MAJOR}" ]; then
  echo "ERROR: Major version upgrade is not allowed (${CURRENT_MAJOR}.x -> ${TARGET_MAJOR}.x)"
  exit 1
fi

if [ "${AGENT_MODE}" = "sensor" ]; then
  echo "ALLOWED: Sensor mode upgrade"
  exit 0
fi

BLACKLIST_URL="${DOWNLOAD_URL}/api/v2/upgrade/blacklist.csv"
echo "Downloading upgrade blacklist from ${BLACKLIST_URL}..."
CSV_CONTENT=$(curl -sSfL "${BLACKLIST_URL}") || {
  echo "ERROR: Failed to download blacklist from ${BLACKLIST_URL}"
  exit 1
}

if [ -z "${CSV_CONTENT}" ]; then
  echo "ERROR: Blacklist CSV is empty"
  exit 1
fi

printf '%s\n' "${CSV_CONTENT}" | awk \
  -v current="${CURRENT_VERSION}" \
  -v target="${TARGET_VERSION}" \
  -F, '
  function ver_score(v_str,    parts, score) {
    gsub(/[<=> ]/, "", v_str)
    split(v_str, parts, ".")
    return (parts[1] * 1000000) + (parts[2] * 1000) + parts[3]
  }
  function matches(ver_val, rule_raw,    rule_val) {
    gsub(/^[ \t]+|[ \t]+$/, "", rule_raw)
    rule_val = ver_score(rule_raw)
    if (index(rule_raw, ">=") == 1) return ver_val >= rule_val
    if (index(rule_raw, "<=") == 1) return ver_val <= rule_val
    return ver_val == rule_val
  }
  BEGIN {
    c_score = ver_score(current)
    t_score = ver_score(target)
    blocked = 0
  }
  {
    if ($0 ~ /^#/ || NF < 2) next
    if ((matches(c_score, $1) && matches(t_score, $2)) ||
        (matches(c_score, $2) && matches(t_score, $1))) {
      print "ERROR: Upgrade " current " -> " target " is blocked by rule: [" $0 "]"
      blocked = 1
      exit 1
    }
  }
  END {
    if (blocked == 0) {
      print "ALLOWED: Upgrade " current " -> " target " passed blacklist check"
      exit 0
    }
  }
'
