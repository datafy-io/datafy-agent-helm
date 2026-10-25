#!/usr/bin/env bash
# Pull every image a chart renders on the runner (with retries) and load it into kind,
# so the cluster never pulls from public.ecr.aws itself and can't hit its 429 rate limit.
# Install with agent.image.pullPolicy=IfNotPresent, or the kubelet still goes to the registry.
#
# Usage: preload-kind-images.sh <chart> [helm template args...]
# Env:   KIND_CLUSTER (default: chart-testing, the helm/kind-action default)
set -euo pipefail

CHART=${1:?usage: $0 <chart> [helm template args...]}
shift
CLUSTER=${KIND_CLUSTER:-chart-testing}

# "image: repo:tag" lines, plus "repository:" / "tag:" pairs in controller config (csi_proxy).
mapfile -t IMAGES < <(
  helm template preload "$CHART" "$@" | awk '
    /^[[:space:]]*image:[[:space:]]*"?[^"[:space:]]+:[^"[:space:]]+"?[[:space:]]*$/ {
      v = $2; gsub(/"/, "", v); print v; next
    }
    /^[[:space:]]*repository:/ { repo = $2; gsub(/"/, "", repo); next }
    /^[[:space:]]*tag:/ && repo != "" { t = $2; gsub(/"/, "", t); print repo ":" t; repo = "" }
  ' | sort -u
)

if [[ ${#IMAGES[@]} -eq 0 ]]; then
  echo "No images found in rendered chart $CHART" >&2
  exit 1
fi

for img in "${IMAGES[@]}"; do
  for attempt in 1 2 3 4 5 6; do
    if docker pull -q "$img"; then
      break
    fi
    if [[ $attempt -eq 6 ]]; then
      echo "Failed to pull $img after $attempt attempts" >&2
      exit 1
    fi
    delay=$((attempt * 20))
    echo "Pull of $img failed (attempt $attempt), retrying in ${delay}s" >&2
    sleep "$delay"
  done
  kind load docker-image "$img" --name "$CLUSTER"
done
