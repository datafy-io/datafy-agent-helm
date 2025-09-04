#!/bin/sh
set -e

patch() {
  echo "patching..."
  if [ -n "$IAC_URL" ]; then
    IAC_URL_ENV="{\"name\": \"DATAFY_IAC_URL\", \"value\": \"$IAC_URL\"},"
  fi

  if ! kubectl -n "$K8S_CSI_NAMESPACE" patch deployment ebs-csi-controller --type='json' -p="[$(
  DAEMONSET_JSON="$(kubectl -n "$K8S_CSI_NAMESPACE" get deployment ebs-csi-controller -o json | jq 'del(.metadata.annotations)')"
  DATAFY_CONTAINER_INDEX="$(echo "$DAEMONSET_JSON" | jq '.spec.template.spec.containers | map(.name == "datafy-proxy") | index(true)')";
  EBS_PLUGIN_CONTAINER_INDEX="$(echo "$DAEMONSET_JSON" | jq '.spec.template.spec.containers | map(.name == "ebs-plugin") | index(true)')";
  EBS_PLUGIN_ENV_INDEX="$(echo "$DAEMONSET_JSON" | jq ".spec.template.spec.containers[$EBS_PLUGIN_CONTAINER_INDEX].env | map(.name == \"CSI_ENDPOINT\") | index(true)")";
  CSI_ENDPOINT="$(echo "$DAEMONSET_JSON" | jq -r ".spec.template.spec.containers[$EBS_PLUGIN_CONTAINER_INDEX].env[$EBS_PLUGIN_ENV_INDEX].value")";
  CSI_ENDPOINT_DIR="$(dirname "$(echo "$CSI_ENDPOINT" | sed "s|^unix:/*|/|")")";
  CSI_ENDPOINT_VOLUME_MOUNT="$(echo "$DAEMONSET_JSON" | jq ".spec.template.spec.containers[$EBS_PLUGIN_CONTAINER_INDEX].volumeMounts[] | select(.mountPath | startswith(\"$CSI_ENDPOINT_DIR\"))")";
  if [ -z "$CSI_ENDPOINT_VOLUME_MOUNT" ]; then
    CSI_ENDPOINT_VOLUME_MOUNT="$(echo "$DAEMONSET_JSON" | jq ".spec.template.spec.containers[$EBS_PLUGIN_CONTAINER_INDEX].volumeMounts[] | select(.name == \"socket-dir\" or .name == \"plugin-dir\")")";
  fi;
  CSI_ENDPOINT="$(echo "$CSI_ENDPOINT" | sed "s/2\\.sock/.sock/")";
  NEW_CSI_ENDPOINT="$(echo "$CSI_ENDPOINT" | sed "s/\\.sock/2.sock/")";
  REMOVE_OPS="";
  if [ "$DATAFY_CONTAINER_INDEX" != "null" ]; then
    REMOVE_OPS="$REMOVE_OPS"'{"op": "remove", "path": "/spec/template/spec/containers/'"$DATAFY_CONTAINER_INDEX"'"},';
  fi;
  cat <<EOF
$REMOVE_OPS
{
  "op": "replace",
  "path": "/spec/template/spec/containers/$EBS_PLUGIN_CONTAINER_INDEX/env/$EBS_PLUGIN_ENV_INDEX/value",
  "value": "$NEW_CSI_ENDPOINT"
},
{
  "op": "add",
  "path": "/spec/template/spec/containers/-",
  "value": {
    "name": "datafy-proxy",
    "image": "$K8S_CSI_IMAGE",
    "imagePullPolicy": "Always",
    "args": [ "controller" ],
    "env": [
      {
        "name": "CSI_ENDPOINT",
        "value": "$CSI_ENDPOINT"
      },
      {
        "name": "DEST_ADDRESS",
        "value": "$NEW_CSI_ENDPOINT"
      },
      $IAC_URL_ENV
      {
        "name": "DATAFY_TOKEN",
        "valueFrom": {
          "secretKeyRef":{
            "name": "$DATAFY_TOKEN_SECRET_NAME",
            "key": "$DATAFY_TOKEN_SECRET_KEY"
          }
        }
      },
      {
        "name": "CSI_VERSION",
        "valueFrom": {
          "fieldRef": {
            "apiVersion": "v1",
            "fieldPath": "metadata.labels['app.kubernetes.io/version']"
          }
        }
      }
    ],
    "readinessProbe": {
      "failureThreshold": 5,
      "grpc":{
        "port": 50050,
        "service": ""
      },
      "periodSeconds": 30,
      "successThreshold": 1,
      "timeoutSeconds": 10
    },
    "resources": {
      "limits": { "memory": "256Mi" },
      "requests": { "cpu": "10m", "memory": "40Mi" }
    },
    "volumeMounts": [
      $CSI_ENDPOINT_VOLUME_MOUNT
    ]
  }
}
EOF
  )]"; then
    echo >&2
    echo "ERROR: 'ebs-csi-controller' failed to install" >&2
    echo >&2
    exit 1
  fi

  if ! kubectl -n "$K8S_CSI_NAMESPACE" patch daemonset ebs-csi-node --type='json' -p="[$(
  DAEMONSET_JSON="$(kubectl -n "$K8S_CSI_NAMESPACE" get daemonset ebs-csi-node -o json | jq 'del(.metadata.annotations)')"
  DATAFY_VOLUME_INDEX=$(echo "$DAEMONSET_JSON" | jq '.spec.template.spec.volumes | map(.name == "run-datafy-dir") | index(true)');
  DATAFY_CONTAINER_INDEX=$(echo "$DAEMONSET_JSON" | jq '.spec.template.spec.containers | map(.name == "datafy-proxy") | index(true)');
  EBS_PLUGIN_CONTAINER_INDEX=$(echo "$DAEMONSET_JSON" | jq '.spec.template.spec.containers | map(.name == "ebs-plugin") | index(true)');
  EBS_PLUGIN_ENV_INDEX=$(echo "$DAEMONSET_JSON" | jq ".spec.template.spec.containers[$EBS_PLUGIN_CONTAINER_INDEX].env | map(.name == \"CSI_ENDPOINT\") | index(true)");
  CSI_ENDPOINT="$(echo "$DAEMONSET_JSON" | jq -r ".spec.template.spec.containers[$EBS_PLUGIN_CONTAINER_INDEX].env[$EBS_PLUGIN_ENV_INDEX].value")";
  CSI_ENDPOINT_DIR="$(dirname "$(echo "$CSI_ENDPOINT" | sed "s|^unix:/*|/|")")";
  CSI_ENDPOINT_VOLUME_MOUNT="$(echo "$DAEMONSET_JSON" | jq ".spec.template.spec.containers[$EBS_PLUGIN_CONTAINER_INDEX].volumeMounts[] | select(.mountPath | startswith(\"$CSI_ENDPOINT_DIR\"))")";
  if [ -z "$CSI_ENDPOINT_VOLUME_MOUNT" ]; then
    CSI_ENDPOINT_VOLUME_MOUNT="$(echo "$DAEMONSET_JSON" | jq ".spec.template.spec.containers[$EBS_PLUGIN_CONTAINER_INDEX].volumeMounts[] | select(.name == \"socket-dir\" or .name == \"plugin-dir\")")";
  fi;
  CSI_ENDPOINT="$(echo "$CSI_ENDPOINT" | sed "s/2\\.sock/.sock/")";
  NEW_CSI_ENDPOINT="$(echo "$CSI_ENDPOINT" | sed "s/\\.sock/2.sock/")";
  KUBELET_DIR_NAME="$(echo "$DAEMONSET_JSON" | jq -r ".spec.template.spec.volumes[] | select(.hostPath.path == \"/var/lib/kubelet\").name")";
  REMOVE_OPS="";
  if [ "$DATAFY_VOLUME_INDEX" != "null" ]; then
    REMOVE_OPS="$REMOVE_OPS"'{"op": "remove", "path": "/spec/template/spec/volumes/'"$DATAFY_VOLUME_INDEX"'"},';
  fi;
  if [ "$DATAFY_CONTAINER_INDEX" != "null" ]; then
    REMOVE_OPS="$REMOVE_OPS"'{"op": "remove", "path": "/spec/template/spec/containers/'"$DATAFY_CONTAINER_INDEX"'"},';
  fi;
  cat <<EOF
$REMOVE_OPS
{
  "op": "replace",
  "path": "/spec/template/spec/containers/$EBS_PLUGIN_CONTAINER_INDEX/env/$EBS_PLUGIN_ENV_INDEX/value",
  "value": "$NEW_CSI_ENDPOINT"
},
{
  "op": "add",
  "path": "/spec/template/spec/containers/-",
  "value": {
    "name": "datafy-proxy",
    "image": "$K8S_CSI_IMAGE",
    "imagePullPolicy": "Always",
    "args": [ "node" ],
    "env": [
      {
        "name": "CSI_ENDPOINT",
        "value": "$CSI_ENDPOINT"
      },
      {
        "name": "DEST_ADDRESS",
        "value": "$NEW_CSI_ENDPOINT"
      },
      $IAC_URL_ENV
      {
        "name": "DATAFY_TOKEN",
        "valueFrom": {
          "secretKeyRef":{
            "name": "$DATAFY_TOKEN_SECRET_NAME",
            "key": "$DATAFY_TOKEN_SECRET_KEY"
          }
        }
      },
      {
        "name": "CSI_VERSION",
        "valueFrom": {
          "fieldRef": {
            "apiVersion": "v1",
            "fieldPath": "metadata.labels['app.kubernetes.io/version']"
          }
        }
      }
    ],
    "readinessProbe": {
      "failureThreshold": 5,
      "grpc":{
        "port": 50050,
        "service": ""
      },
      "periodSeconds": 30,
      "successThreshold": 1,
      "timeoutSeconds": 10
    },
    "resources": {
      "limits": { "memory": "256Mi" },
      "requests": { "cpu": "10m", "memory": "40Mi" }
    },
    "securityContext": {
      "privileged": true,
      "readOnlyRootFilesystem": true
    },
    "volumeMounts": [
      {
        "mountPath": "/var/lib/kubelet",
        "mountPropagation": "Bidirectional",
        "name": "$KUBELET_DIR_NAME"
      },
      $CSI_ENDPOINT_VOLUME_MOUNT,
      {
        "mountPath": "/dev",
        "name": "device-dir"
      },
      {
        "mountPath": "/run/datafy",
        "name": "run-datafy-dir"
      }
    ]
  }
},
{
  "op": "add",
  "path": "/spec/template/spec/volumes/-",
  "value": {
    "name": "run-datafy-dir",
    "hostPath": {
      "path": "/run/datafy",
      "type": "Directory"
    }
  }
}
EOF
  )]"; then
    echo >&2
    echo "ERROR: 'ebs-csi-node' failed to install" >&2
    echo >&2
    exit 1
  fi

}

unpatch() {
  echo "unpatching..."
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
}

if ! kubectl get deployment -n "$K8S_CSI_NAMESPACE" ebs-csi-controller > /dev/null 2>&1 || ! kubectl get daemonset -n "$K8S_CSI_NAMESPACE" ebs-csi-node > /dev/null 2>&1; then
  echo "Error: EBS CSI driver is not installed." >&2
  exit 1
fi

env

case "$HOOK_EVENT" in
  post-install|post-upgrade)
    AGENT_MODE=$(echo "${AGENT_MODE}" | tr '[:upper:]' '[:lower:]')
    case "$AGENT_MODE" in
      sensor) unpatch ;;
      autoscaler) patch ;;
    esac
  ;;
  pre-delete)
    unpatch
  ;;
esac
