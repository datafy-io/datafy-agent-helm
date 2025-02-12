#!/bin/sh
set -e

if kubectl get deployment -n "$K8S_CSI_NAMESPACE" ebs-csi-controller > /dev/null 2>&1; then
  kubectl -n "$K8S_CSI_NAMESPACE" patch deployment ebs-csi-controller --type='json' -p="[$(
    DAEMONSET_JSON="$(kubectl -n "$K8S_CSI_NAMESPACE" get deployment ebs-csi-controller -o json | jq 'del(.metadata.annotations)')"
    DATAFY_CONTAINER_INDEX="$(echo "$DAEMONSET_JSON" | jq '.spec.template.spec.containers | map(.name == "datafy-proxy") | index(true)')";
    EBS_PLUGIN_CONTAINER_INDEX="$(echo "$DAEMONSET_JSON" | jq '.spec.template.spec.containers | map(.name == "ebs-plugin") | index(true)')";
    EBS_PLUGIN_ENV_INDEX="$(echo "$DAEMONSET_JSON" | jq ".spec.template.spec.containers[$EBS_PLUGIN_CONTAINER_INDEX].env | map(.name == \"CSI_ENDPOINT\") | index(true)")";
    CSI_ENDPOINT="$(echo "$DAEMONSET_JSON" | jq -r ".spec.template.spec.containers[$EBS_PLUGIN_CONTAINER_INDEX].env[$EBS_PLUGIN_ENV_INDEX].value")";
    NEW_CSI_ENDPOINT="$(echo "$CSI_ENDPOINT" | sed "s/2\\.sock/.sock/")";
    if [ "$DATAFY_CONTAINER_INDEX" != "null" ]; then
      cat <<EOF
{
"op": "remove",
"path": "/spec/template/spec/containers/$DATAFY_CONTAINER_INDEX"
},
{
"op": "replace",
"path": "/spec/template/spec/containers/$EBS_PLUGIN_CONTAINER_INDEX/env/$EBS_PLUGIN_ENV_INDEX/value",
"value": "$NEW_CSI_ENDPOINT"
}
EOF
    fi;
)]"
fi

if kubectl get daemonset -n "$K8S_CSI_NAMESPACE" ebs-csi-node > /dev/null 2>&1; then
  kubectl -n "$K8S_CSI_NAMESPACE" patch daemonset ebs-csi-node --type='json' -p="[$(
    DAEMONSET_JSON="$(kubectl -n "$K8S_CSI_NAMESPACE" get daemonset ebs-csi-node -o json | jq 'del(.metadata.annotations)')"
    DATAFY_VOLUME_INDEX=$(echo "$DAEMONSET_JSON" | jq '.spec.template.spec.volumes | map(.name == "run-datafy-dir") | index(true)');
    DATAFY_CONTAINER_INDEX=$(echo "$DAEMONSET_JSON" | jq '.spec.template.spec.containers | map(.name == "datafy-proxy") | index(true)');
    EBS_PLUGIN_CONTAINER_INDEX=$(echo "$DAEMONSET_JSON" | jq '.spec.template.spec.containers | map(.name == "ebs-plugin") | index(true)');
    EBS_PLUGIN_ENV_INDEX=$(echo "$DAEMONSET_JSON" | jq ".spec.template.spec.containers[$EBS_PLUGIN_CONTAINER_INDEX].env | map(.name == \"CSI_ENDPOINT\") | index(true)");
    CSI_ENDPOINT="$(echo "$DAEMONSET_JSON" | jq -r ".spec.template.spec.containers[$EBS_PLUGIN_CONTAINER_INDEX].env[$EBS_PLUGIN_ENV_INDEX].value")";
    NEW_CSI_ENDPOINT="$(echo "$CSI_ENDPOINT" | sed "s/2\\.sock/.sock/")";
    if [ "$DATAFY_VOLUME_INDEX" != "null" ] && [ "$DATAFY_CONTAINER_INDEX" != "null" ]; then
      cat <<EOF
{
"op": "remove",
"path": "/spec/template/spec/volumes/$DATAFY_VOLUME_INDEX"
},
{
"op": "remove",
"path": "/spec/template/spec/containers/$DATAFY_CONTAINER_INDEX"
},
{
"op": "replace",
"path": "/spec/template/spec/containers/$EBS_PLUGIN_CONTAINER_INDEX/env/$EBS_PLUGIN_ENV_INDEX/value",
"value": "$NEW_CSI_ENDPOINT"
}
EOF
    fi;
)]"
fi
