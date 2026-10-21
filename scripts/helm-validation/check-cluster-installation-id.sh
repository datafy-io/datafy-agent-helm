#!/usr/bin/env bash
# Checks the live datafy-agent release: every resource in its manifest carries the
# same datafy.io/installation-id, matching DATAFY_INSTALLATION_ID on the controller.
# Prints the ID on stdout. With a previous ID, also fails if the ID did not change.
#
# Usage: scripts/helm-validation/check-cluster-installation-id.sh <namespace> [previous-id]
set -euo pipefail

NS="$1"
PREV="${2:-}"
status=0
id=""

while IFS=$'\t' read -r kind name rns; do
  [[ -z "$kind" ]] && continue
  got=$(kubectl get "$kind" "$name" -n "${rns:-$NS}" -o jsonpath='{.metadata.labels.datafy\.io/installation-id}')
  echo "  $kind/$name: ${got:-<missing>}" >&2
  if [[ -z "$got" ]]; then
    echo "$kind/$name is missing datafy.io/installation-id" >&2
    status=1
  elif [[ -z "$id" ]]; then
    id="$got"
  elif [[ "$got" != "$id" ]]; then
    echo "$kind/$name has installation-id $got, expected $id" >&2
    status=1
  fi
done < <(helm get manifest datafy-agent -n "$NS" | yq -r 'select(.kind != null) | [.kind, .metadata.name, (.metadata.namespace // "")] | @tsv')

if kubectl get deploy datafy-controller -n "$NS" >/dev/null 2>&1; then
  env_id=$(kubectl get deploy datafy-controller -n "$NS" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="controller")].env[?(@.name=="DATAFY_INSTALLATION_ID")].value}')
  echo "  controller DATAFY_INSTALLATION_ID: ${env_id:-<missing>}" >&2
  if [[ "$env_id" != "$id" ]]; then
    echo "DATAFY_INSTALLATION_ID is '$env_id', expected $id" >&2
    status=1
  fi
fi

if [[ -n "$PREV" && "$id" == "$PREV" ]]; then
  echo "installation-id did not change: still $id" >&2
  status=1
fi

if [[ $status -ne 0 ]]; then
  exit $status
fi
echo "installation-id OK: $id${PREV:+ (previous $PREV)}" >&2
echo "$id"
