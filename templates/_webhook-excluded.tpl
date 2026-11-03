{{/*
Pods the pod mutation webhook skips by default, as an ordered list of objectSelector rules.
Each rule renders "<key> NotIn <values>" and is extended by
controller.webhook.excluded.podLabels.<key>.

The webhook fails closed, so creating these pods must not depend on the controller being
reachable: they are node-level components that other pods on the node need to start, get an
IP, resolve names, reach Services, mount volumes, get AWS credentials or use devices, plus
admission webhooks that fail closed themselves. Skipped pods get no Datafy tolerations and no
Datafy handling of their volumes, so never list the EBS CSI driver pods (ebs-csi-node,
ebs-csi-controller): the webhook injects the Datafy sidecar into them.
*/}}
{{- define "datafy-agent.webhook.builtinExcludedPodLabels" -}}
rules:
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
{{- $namespaces := (((.Values.controller).webhook).excluded).namespaces | default list }}
{{- if not (kindIs "slice" $namespaces) }}
{{- fail "controller.webhook.excluded.namespaces must be a list of namespace names (with --set: excluded.namespaces={my-ns,other-ns})" }}
{{- end }}
- key: "datafy.io/webhook"
  operator: "NotIn"
  values:
    - "disabled"
{{- with $namespaces | compact | uniq }}
- key: "kubernetes.io/metadata.name"
  operator: "NotIn"
  values:
    {{- range . }}
    - {{ . | quote }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
objectSelector matchExpressions of the pod mutation webhook: the built-in rules merged with
controller.webhook.excluded.podLabels. User values for the key of a built-in rule extend that
rule; every other user key renders one NotIn expression, sorted by key.
*/}}
{{- define "datafy-agent.webhook.objectSelectorExpressions" -}}
{{- $podLabels := (((.Values.controller).webhook).excluded).podLabels | default dict }}
{{- range $key, $values := $podLabels }}
{{- if and $values (not (kindIs "slice" $values)) }}
{{- fail (printf "controller.webhook.excluded.podLabels.%s must be a list of label values (with --set, escape dots in the label key: podLabels.app\\.kubernetes\\.io/name={...})" $key) }}
{{- end }}
{{- end }}
{{- $merged := list }}
{{- range $rule := (include "datafy-agent.webhook.builtinExcludedPodLabels" . | fromYaml).rules }}
{{- $merged = append $merged $rule.key }}
{{- $values := $rule.values }}
{{- range get $podLabels $rule.key | default list | compact }}
{{- if not (has . $values) }}
{{- $values = append $values . }}
{{- end }}
{{- end }}
- key: {{ $rule.key | quote }}
  operator: "NotIn"
  values:
    {{- range $values }}
    - {{ . | quote }}
    {{- end }}
{{- end }}
{{- range $key := keys $podLabels | sortAlpha }}
{{- if not (has $key $merged) }}
{{- with get $podLabels $key | default list | compact | uniq }}
- key: {{ $key | quote }}
  operator: "NotIn"
  values:
    {{- range . }}
    - {{ . | quote }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
