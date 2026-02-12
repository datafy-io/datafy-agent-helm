#!/usr/bin/env sh

TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
APISERVER="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"

DATAFY_LABEL="${DATAFY_LABEL:-datafy.io/install}"

if [ -z "${NODE_NAME}" ]; then
  echo "ERROR: NODE_NAME env var is required"
  exit 1
fi

if [ -z "${AGENT_MODE}" ]; then
  echo "ERROR: AGENT_MODE env var is required"
  exit 1
fi

get_node_label_value() {
  _tmp="$(mktemp)"

  http_code=$(curl -sS --cacert "${CACERT}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/json" \
    -o "${_tmp}" \
    -w '%{http_code}' \
    -X GET "${APISERVER}/api/v1/nodes/${NODE_NAME}" || echo "000")

  if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
    body="$(cat "${_tmp}" 2>/dev/null)"
    rm -f "${_tmp}" || true
    echo "ERROR: failed to GET node (http=${http_code}). Response: ${body}"
    return 1
  fi

  val=$(cat $_tmp | sed -n '/"labels"[[:space:]]*:[[:space:]]*{/,/}[[:space:]]*,/p' | grep "$1" | cut -d "\"" -f 4)
  rm -f "${_tmp}" || true
  echo "${val}"
}

patch_node_or_die() {
  _payload="$1"
  _tmp="$(mktemp)"

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

  body="$(cat "${_tmp}" 2>/dev/null)"
  rm -f "${_tmp}" || true

  echo "ERROR: node patch failed (http=${http_code}). Response:"
  echo ${body}
  return 1
}

insert_label() {
  current="$(get_node_label_value "${DATAFY_LABEL}" || true)"

  if [ "${current}" = "${AGENT_MODE}" ]; then
    echo "label '${DATAFY_LABEL}:${AGENT_MODE}' already set (skipping patch)"
    return 0
  fi

  echo "labeling node ${NODE_NAME} with '${DATAFY_LABEL}:${AGENT_MODE}'"
  patch_node_or_die '{"metadata":{"labels":{"'${DATAFY_LABEL}'":"'"${AGENT_MODE}"'"}}}'
}

remove_label() {
  current="$(get_node_label_value "${DATAFY_LABEL}" || true)"
  if [ -z "${current}" ]; then
    echo "label '${DATAFY_LABEL}' not present (skipping removal)"
    return 0
  fi

  echo "removing label '${DATAFY_LABEL}' from node ${NODE_NAME}"
  patch_node_or_die '{"metadata":{"labels":{"'${DATAFY_LABEL}'":null}}}' || {
    # Best-effort during failure paths: don't mask the original error.
    echo "label removal failed (continuing)"
    return 0
  }
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
