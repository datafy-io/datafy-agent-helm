#!/usr/bin/env bash
set -euo pipefail

NS="${1:-default}"

# if the install marker exists, the chart is still considered installed
if kubectl get configmap datafy-install-marker -n "${NS}" >/dev/null 2>&1; then
  echo "Refusing to cleanup: configmap 'datafy-install-marker' exists in namespace '${NS}'."
  echo "Uninstall first by running 'helm uninstall datafy -n ${NS}'."
  exit 1
fi

echo "Deleting Datafy [namespace ${NS}] kept resources"

# Namespaced resources
kubectl delete service datafy-controller-webhook -n "${NS}" --ignore-not-found
kubectl delete service datafy-controller -n "${NS}" --ignore-not-found
kubectl delete deployment datafy-controller -n "${NS}" --ignore-not-found
kubectl delete configmap datafy-controller-config -n "${NS}" --ignore-not-found
kubectl delete configmap datafy-volume-replacements -n "${NS}" --ignore-not-found
kubectl delete secret datafy-controller-webhook-tls -n "${NS}" --ignore-not-found
kubectl delete secret datafy-token -n "${NS}" --ignore-not-found
kubectl delete serviceaccount datafy-controller-sa -n "${NS}" --ignore-not-found

# Cluster-scoped resources
kubectl delete clusterrolebinding datafy-controller-binding --ignore-not-found
kubectl delete clusterrole datafy-controller-role --ignore-not-found
kubectl delete mutatingwebhookconfiguration datafy-controller-webhook --ignore-not-found

csi_namespace=$(kubectl get deployment,daemonset -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,KIND:.kind --no-headers 2>/dev/null \
  | awk '($2=="ebs-csi-controller" && $3=="Deployment") || ($2=="ebs-csi-node" && $3=="DaemonSet") {print $1}' \
  | sort -u
)
if [[ -n "$csi_namespace" ]]; then
  echo "Deleting Datafy [namespace ${csi_namespace}] kept resources"
  kubectl delete configmap datafy-volume-replacements -n "${csi_namespace}" --ignore-not-found
  kubectl delete secret datafy-token -n "${csi_namespace}" --ignore-not-found

  echo "Patching AWS EBS CSI [namespace ${csi_namespace}] labels and annotations"
  kubectl patch deployment ebs-csi-controller -n "$csi_namespace" --type=json -p='[
    {"op":"remove","path":"/spec/template/metadata/labels/datafy.io~1install"},
    {"op":"remove","path":"/spec/template/metadata/annotations/datafy.io~1config-sha"},
    {"op":"remove","path":"/spec/template/metadata/annotations/datafy.io~1transparent"}
  ]' >/dev/null 2>&1 || true
  kubectl patch daemonset ebs-csi-node -n "$csi_namespace" --type=json -p='[
    {"op":"remove","path":"/spec/template/metadata/labels/datafy.io~1install"},
    {"op":"remove","path":"/spec/template/metadata/annotations/datafy.io~1config-sha"},
    {"op":"remove","path":"/spec/template/metadata/annotations/datafy.io~1transparent"}
  ]' >/dev/null 2>&1 || true
else
  echo "No CSI Driver workloads detected for patching."
fi

echo
echo "Done."
