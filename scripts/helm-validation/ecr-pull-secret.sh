#!/usr/bin/env bash
# Creates the ecr-pull image pull secret in each namespace, for pulling the
# controller image from the private ECR registry.
#
# Usage: scripts/helm-validation/ecr-pull-secret.sh <registry> <namespace>...
set -euo pipefail

REGISTRY="$1"; shift
PASSWORD=$(aws ecr get-login-password)

for ns in "$@"; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret docker-registry ecr-pull -n "$ns" \
    --docker-server="$REGISTRY" --docker-username=AWS --docker-password="$PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
done
