#!/usr/bin/env bash
# Every image the chart renders must already be in the registry, for every platform we ship.
#
# The release orchestrator tags this repo together with the agent and controller repos, and their builds
# take up to 40 minutes. The chart is published only after they finished; this is the proof that they
# really produced each image this chart version names, before the chart goes to the index.
#
# Usage: check-images-exist.sh <chart> [helm template args...]
# Env:   PLATFORMS (default: "amd64 arm64"), ATTEMPTS (default: 3)
set -euo pipefail

CHART=${1:?usage: $0 <chart> [helm template args...]}
shift
PLATFORMS=${PLATFORMS:-amd64 arm64}
ATTEMPTS=${ATTEMPTS:-3}

# Same extraction as preload-kind-images.sh (keep the two in sync):
# "image: repo:tag" lines, plus "repository:" / "tag:" pairs in controller config (csi_proxy).
IMAGES=$(
  helm template check "$CHART" "$@" | awk '
    /^[[:space:]]*image:[[:space:]]*"?[^"[:space:]]+:[^"[:space:]]+"?[[:space:]]*$/ {
      v = $2; gsub(/"/, "", v); print v; next
    }
    /^[[:space:]]*repository:/ { repo = $2; gsub(/"/, "", repo); next }
    /^[[:space:]]*tag:/ && repo != "" { t = $2; gsub(/"/, "", t); print repo ":" t; repo = "" }
  ' | sort -u
)

if [[ -z "$IMAGES" ]]; then
  echo "No images found in rendered chart $CHART" >&2
  exit 1
fi

ERR=$(mktemp)
trap 'rm -f "$ERR"' EXIT

failed=0
for img in $IMAGES; do
  manifest=""
  for attempt in $(seq 1 "$ATTEMPTS"); do
    if manifest=$(docker manifest inspect "$img" 2>"$ERR"); then
      break
    fi
    manifest=""
    [[ $attempt -lt $ATTEMPTS ]] && sleep $((attempt * 10))
  done
  if [[ -z "$manifest" ]]; then
    echo "MISSING  $img  ($(tr '\n' ' ' <"$ERR"))" >&2
    failed=1
    continue
  fi
  missing_platforms=""
  for p in $PLATFORMS; do
    grep -Eq "\"architecture\":[[:space:]]*\"$p\"" <<<"$manifest" || missing_platforms+=" $p"
  done
  if [[ -n "$missing_platforms" ]]; then
    echo "PARTIAL  $img  (no image for:$missing_platforms)" >&2
    failed=1
  else
    echo "ok       $img  ($PLATFORMS)"
  fi
done

if [[ $failed -ne 0 ]]; then
  echo "The chart names images that are not in the registry (yet). It must not be published." >&2
  exit 1
fi
