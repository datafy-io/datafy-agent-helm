#!/usr/bin/env bash
# Prints the state of a namespace: pods, recent events, details of pods that are
# not ready, and controller logs (current and previous container).
#
# Usage: scripts/helm-validation/snapshot.sh <namespace>
NS="$1"

echo "::group::Snapshot $NS $(date -u +%H:%M:%S)"
kubectl get pods -n "$NS" -o wide 2>/dev/null || echo "(namespace not created yet)"

echo "--- recent events ---"
kubectl get events -n "$NS" --sort-by=.lastTimestamp 2>/dev/null | tail -25 || true

echo "--- pods not ready ---"
for p in $(kubectl get pods -n "$NS" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"\n"}{end}' 2>/dev/null | awk '$2!="True"{print $1}'); do
  echo ">>> describe $p"
  kubectl describe pod -n "$NS" "$p" | sed -n '/^Containers:/,/^Volumes:/p;/^Events:/,$p' | tail -60
done

echo "--- controller logs ---"
for p in $(kubectl get pods -n "$NS" -l app.kubernetes.io/name=datafy-controller -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  echo ">>> $p (current)"
  kubectl logs -n "$NS" "$p" -c controller --tail=60 2>&1 || true
  echo ">>> $p (previous)"
  kubectl logs -n "$NS" "$p" -c controller --previous --tail=60 2>&1 || true
done
echo "::endgroup::"
