{{/*
Pods the pod mutation webhook always skips: Datafy's own pods and AWS-native node components.
Never list the EBS CSI driver pods: the webhook injects the Datafy sidecar into them.
*/}}
{{- define "datafy-agent.webhook.defaultPodMatchExpressions" -}}
expressions:
  - key: app.kubernetes.io/name
    values:
      - datafy-controller
      - datafy-agent
      - aws-cluster-autoscaler
      - aws-node
      - eks-pod-identity-agent
      - eks-pod-identity-agent-hybrid
      - eks-pod-identity-agent-hybrid-bottlerocket
  - key: k8s-app
    values:
      - kube-dns
      - kube-proxy
      - coredns
      - aws-node
  - key: app
    values:
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
Pods the pod mutation webhook also skips unless controller.webhook.excluded.extraEnabled is false:
non-AWS node components (CNIs, service mesh, DNS cache, device plugins) and Kyverno.
*/}}
{{- define "datafy-agent.webhook.extraPodMatchExpressions" -}}
expressions:
  - key: app.kubernetes.io/name
    values:
      - cilium-operator
      - cilium-node-init
      - ztunnel-cilium
      - nvidia-device-plugin
      - kyverno-admission-controller
      - kyverno-background-controller
      - kyverno-cleanup-controller
      - kyverno-reports-controller
  - key: k8s-app
    values:
      - node-local-dns
      - calico-node
      - calico-typha
      - canal
      - cilium
      - cilium-envoy
      - kube-router
      - kindnet
      - istio-cni-node
      - linkerd-cni
  - key: app
    values:
      - flannel
      - antrea
      - multus
      - kube-ovn-cni
      - kube-ovn-controller
      - ovn-central
      - ztunnel
      - kuma-cni
      - kong-mesh-cni
      - consul
      - istiod
{{- end }}

{{/*
objectSelector matchExpressions of the pod mutation webhook: the default expressions, then the extra
ones unless controller.webhook.excluded.extraEnabled is false, then
controller.webhook.excluded.podMatchExpressions in order, one expression per entry. Entries are
not merged by key: expressions are ANDed, so two NotIn expressions on one key skip the union
of their values. The operator defaults to NotIn; values.schema.json restricts it to NotIn and
DoesNotExist. Blank and repeated values of an entry are dropped.
*/}}
{{- define "datafy-agent.webhook.objectSelectorExpressions" -}}
{{- $excluded := ((.Values.controller).webhook).excluded | default dict }}
{{- $expressions := (include "datafy-agent.webhook.defaultPodMatchExpressions" . | fromYaml).expressions }}
{{- if ne $excluded.extraEnabled false }}
{{- $expressions = concat $expressions (include "datafy-agent.webhook.extraPodMatchExpressions" . | fromYaml).expressions }}
{{- end }}
{{- $user := $excluded.podMatchExpressions | default list }}
{{- range $expr := concat $expressions $user }}
{{- $operator := $expr.operator | default "NotIn" }}
{{- $values := list }}
{{- range $expr.values }}
{{- $value := ternary "" (toString .) (kindIs "invalid" .) }}
{{- if and $value (not (has $value $values)) }}
{{- $values = append $values $value }}
{{- end }}
{{- end }}
{{- if and (eq $operator "NotIn") (not $values) }}
{{- fail (printf "controller.webhook.excluded.podMatchExpressions: the NotIn expression on %q needs at least one non-empty value" $expr.key) }}
{{- end }}
- key: {{ $expr.key | quote }}
  operator: {{ $operator | quote }}
{{- if eq $operator "NotIn" }}
  values:
    {{- range $values }}
    - {{ . | quote }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}
