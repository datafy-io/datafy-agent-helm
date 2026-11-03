{{/*
Pods the pod mutation webhook skips by default, as an ordered list of objectSelector label
selector requirements in the shape of controller.webhook.excluded.podMatchExpressions.

The webhook fails closed, so creating these pods must not depend on the controller being
reachable: they are node-level components that other pods on the node need to start, get an
IP, resolve names, reach Services, mount volumes, get AWS credentials or use devices, plus
admission webhooks that fail closed themselves. Skipped pods get no Datafy tolerations and no
Datafy handling of their volumes, so never list the EBS CSI driver pods (ebs-csi-node,
ebs-csi-controller): the webhook injects the Datafy sidecar into them.
*/}}
{{- define "datafy-agent.webhook.builtinPodMatchExpressions" -}}
expressions:
  - key: app.kubernetes.io/name
    values:
      # Datafy
      - datafy-controller
      - datafy-agent
      # Node provisioning
      - aws-cluster-autoscaler
      # Pod networking
      - aws-node
      - cilium-operator
      - cilium-node-init
      # Mesh datapath
      - ztunnel-cilium
      # Node credentials
      - eks-pod-identity-agent
      - eks-pod-identity-agent-hybrid
      - eks-pod-identity-agent-hybrid-bottlerocket
      # Device plugins
      - nvidia-device-plugin
      # Admission webhooks that fail closed
      - kyverno-admission-controller
      - kyverno-background-controller
      - kyverno-cleanup-controller
      - kyverno-reports-controller
  - key: k8s-app
    values:
      # DNS and Service routing
      - kube-dns
      - kube-proxy
      - coredns
      - node-local-dns
      # Pod networking
      - aws-node
      - calico-node
      - calico-typha
      - canal
      - cilium
      - cilium-envoy
      - kube-router
      - kindnet
      # Mesh datapath
      - istio-cni-node
      - linkerd-cni
  - key: app
    values:
      # Pod networking
      - flannel
      - antrea
      - multus
      - kube-ovn-cni
      - kube-ovn-controller
      - ovn-central
      # Mesh datapath and its control plane (certificates, injection)
      - ztunnel
      - istiod
      - kuma-cni
      - kong-mesh-cni
      - consul
      # Node volume mounts
      - efs-csi-node
      - fsx-csi-node
      - s3-csi-node
      - secrets-store-csi-driver
      - secrets-store-csi-driver-provider-aws
  - key: datafy.io/webhook
    values:
      - disabled
{{- end }}

{{/*
namespaceSelector matchExpressions of the pod mutation webhook: the datafy.io/webhook=disabled
opt-out label and controller.webhook.excluded.namespaces.
*/}}
{{- define "datafy-agent.webhook.namespaceSelectorExpressions" -}}
- key: "datafy.io/webhook"
  operator: "NotIn"
  values:
    - "disabled"
{{- with (((.Values.controller).webhook).excluded).namespaces | default list | compact | uniq }}
- key: "kubernetes.io/metadata.name"
  operator: "NotIn"
  values:
    {{- range . }}
    - {{ . | quote }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
objectSelector matchExpressions of the pod mutation webhook: the built-in expressions followed
by controller.webhook.excluded.podMatchExpressions in order, one expression per entry. Entries
are not merged by key: expressions are ANDed, so two NotIn expressions on one key skip the union
of their values. The operator defaults to NotIn; values.schema.json restricts it to NotIn and
DoesNotExist. Blank and repeated values of an entry are dropped.
*/}}
{{- define "datafy-agent.webhook.objectSelectorExpressions" -}}
{{- $builtin := (include "datafy-agent.webhook.builtinPodMatchExpressions" . | fromYaml).expressions }}
{{- $user := (((.Values.controller).webhook).excluded).podMatchExpressions | default list }}
{{- range $expr := concat $builtin $user }}
{{- $operator := $expr.operator | default "NotIn" }}
- key: {{ $expr.key | quote }}
  operator: {{ $operator | quote }}
{{- if eq $operator "NotIn" }}
{{- $values := list }}
{{- range $expr.values }}
{{- $value := ternary "" (toString .) (kindIs "invalid" .) }}
{{- if and $value (not (has $value $values)) }}
{{- $values = append $values $value }}
{{- end }}
{{- end }}
{{- if not $values }}
{{- fail (printf "controller.webhook.excluded.podMatchExpressions: the NotIn expression on %q needs at least one non-empty value" $expr.key) }}
{{- end }}
  values:
    {{- range $values }}
    - {{ . | quote }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}
