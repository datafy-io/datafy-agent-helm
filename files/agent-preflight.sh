#!/usr/bin/env sh

TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
APISERVER="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"

if [ -z "${NODE_NAME}" ]; then
  echo "ERROR: NODE_NAME env var is required"
  exit 1
fi

if [ -z "${AGENT_MODE}" ]; then
  echo "ERROR: AGENT_MODE env var is required"
  exit 1
fi

patch_node_or_die() {
  _payload="$1"
  _tmp="$(mktemp)"

  # -sS: silent but still show errors; write server response body to temp file.
  # We don't want successful responses to spam logs.
  http_code=$(curl -sS --cacert "${CACERT}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/merge-patch+json" \
    -o "${_tmp}" \
    -w '%{http_code}' \
    -X PATCH "${APISERVER}/api/v1/nodes/${NODE_NAME}" \
    -d "${_payload}" || echo "000")

  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    rm -f "${_tmp}" || true
    return 0
  fi

  # Non-2xx. Surface response body if present.
  body="$(cat "${_tmp}" 2>/dev/null)"
  rm -f "${_tmp}" || true

  echo "ERROR: node patch failed (http=${http_code}). Response:"
  echo ${body}
  return 1
}

insert_label() {
  echo "labeling node ${NODE_NAME} with 'datafy.io/install:${AGENT_MODE}'"
  patch_node_or_die '{"metadata":{"labels":{"datafy.io/install":"'${AGENT_MODE}'"}}}'
}

remove_label() {
  echo "removing label 'datafy.io/install' from node ${NODE_NAME}"
  if patch_node_or_die '{"metadata":{"labels":{"datafy.io/install":null}}}'; then
    echo "label removal success"
  else
    # Best-effort during failure paths: don't mask the original error.
    echo "label removal failed (continuing)"
    return 0
  fi
}

set +e
/datafy/preflight-check.sh
preflight_rc=$?
set -e

echo

if [ "$preflight_rc" -ne 0 ]; then
  echo "preflight failed (code=$preflight_rc)"
  remove_label
  exit "$preflight_rc"
fi

insert_label
