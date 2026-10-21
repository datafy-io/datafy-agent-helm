#!/usr/bin/env bash
# Every resource the chart renders must carry the datafy.io/installation-id label,
# all with the same value, matching DATAFY_INSTALLATION_ID on the controller.
#
# Usage: scripts/helm-validation/check-installation-id.sh [chart-dir]
set -euo pipefail

CHART="${1:-.}"
LABEL='datafy.io/installation-id'
status=0

check() {
  local name="$1"; shift
  local rendered failed=0
  rendered=$(helm template datafy-agent "$CHART" \
    --set-string agent.token=1 --set-string agent.image.tag=1 \
    --set disableValidation=true "$@")

  local missing
  missing=$(yq -r "select(.kind != null) | select(.metadata.labels[\"$LABEL\"] == null) | .kind + \"/\" + .metadata.name" <<<"$rendered")
  if [[ -n "$missing" ]]; then
    echo "[$name] resources missing $LABEL:" >&2
    echo "$missing" | sed 's/^/  /' >&2
    failed=1
  fi

  local ids
  ids=$( {
    yq -r "select(.kind != null) | .metadata.labels[\"$LABEL\"] // \"\"" <<<"$rendered"
    yq -r 'select(.kind == "Deployment") | .spec.template.spec.containers[].env[] | select(.name == "DATAFY_INSTALLATION_ID") | .value' <<<"$rendered"
  } | grep -v '^---$' | grep -v '^$' | sort -u)
  if [[ $(wc -l <<<"$ids") -ne 1 ]]; then
    echo "[$name] expected one $LABEL value, got:" >&2
    echo "$ids" | sed 's/^/  /' >&2
    failed=1
  fi

  if [[ $failed -eq 1 ]]; then
    status=1
    return
  fi
  echo "[$name] ok: $(yq -r 'select(.kind != null) | .kind' <<<"$rendered" | grep -vc '^---$') resources, id $ids"
}

check autoscaler --set agent.mode=AutoScaler
check sensor --set agent.mode=Sensor
check sensor-no-extended --set agent.mode=Sensor --set extendedInstallOnSensor=false

exit $status
