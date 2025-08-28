{{- define "datafy-agent.validation.mode" }}
  {{- $mode := lower (trim .Values.agent.mode) }}
  {{- if not (or (eq $mode "autoscaler") (eq $mode "sensor")) }}
    {{ fail (printf "invalid value: agent.mode must be either 'autoscaler' or 'sensor', got '%s'" $mode) }}
  {{- end }}
{{- end }}

{{- define "datafy-agent.validation.token" }}
  {{- $hasToken := not (empty (trim (default "" .Values.agent.token))) }}
  {{- $hasExternalSecretName := not (empty (trim (default "" .Values.agent.externalTokenSecret.name))) }}
  {{- $hasExternalSecretKey := not (empty (trim (default "" .Values.agent.externalTokenSecret.key))) }}
  {{- if and (not $hasToken) (not $hasExternalSecretName) }}
    {{ fail "invalid values: one of agent.token or agent.externalTokenSecret.name must be set" }}
  {{- else if and $hasToken $hasExternalSecretName }}
    {{ fail "invalid values: only one of agent.token or agent.externalTokenSecret.name can be set" }}
  {{- end }}
  {{- if and $hasExternalSecretName (not $hasExternalSecretKey) }}
    {{ fail "invalid values: when using agent.externalTokenSecret.name, agent.externalTokenSecret.key must also be set" }}
  {{- end}}

  {{- if $hasExternalSecretName }}
    {{- $hasExternalSecret := lookup "v1" "Secret" .Release.Namespace .Values.agent.externalTokenSecret.name }}
    {{- if not $hasExternalSecret }}
      {{ fail (printf "invalid value: external secret '%s' not found in namespace '%s'" .Values.agent.externalTokenSecret.name .Release.Namespace) }}
    {{- end }}
    {{- $csiNamespace := (include "datafy-agent.ebsCsiProxyNamespace" . ) }}
    {{- if ne .Release.Namespace $csiNamespace }}
      {{- $hasCsiExternalSecret := lookup "v1" "Secret" $csiNamespace .Values.agent.externalTokenSecret.name }}
      {{- if not $hasCsiExternalSecret }}
        {{ fail (printf "invalid value: external secret '%s' not found in namespace '%s'" .Values.agent.externalTokenSecret.name $csiNamespace) }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "datafy-agent.validation.csi" }}
  {{- $hasCsiDriver := or (.Capabilities.APIVersions.Has "storage.k8s.io/v1/CSIDriver") (.Capabilities.APIVersions.Has "storage.k8s.io/v1beta1/CSIDriver") }}
  {{- if .Values.awsEbsCsiDriver.enabled }}
    {{- if and $hasCsiDriver .Release.IsInstall }}
      {{ fail "aws-ebs-csi-driver is already supported in this cluster" }}
    {{- end }}
  {{- else }}}}
    {{- if not $hasCsiDriver }}
      {{ fail "aws-ebs-csi-driver is not supported in this cluster" }}
    {{- else if .Values.ebsCsiProxy.enabled }}
      {{- $ns := (include "datafy-agent.ebsCsiProxyNamespace" . ) }}
      {{- $node := lookup "apps/v1" "DaemonSet" $ns "ebs-csi-node" }}
      {{- $controller := lookup "apps/v1" "Deployment" $ns "ebs-csi-controller" }}
      {{- if or (not $node) (not $controller) }}
        {{ fail (printf "CSI driver not found in namespace %s." $ns) }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
