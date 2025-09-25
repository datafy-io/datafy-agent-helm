{{- define "datafy-agent.validation.mode" }}
  {{- $mode := (include "datafy-agent.agentModeNormalized" . ) }}
  {{- if not (or (eq $mode "autoscaler") (eq $mode "sensor")) }}
    {{ fail (printf "invalid value: agent.mode must be either 'autoscaler' or 'sensor', got '%s'" $mode) }}
  {{- end }}
{{- end }}

{{- define "datafy-agent.validation.token" }}
  {{- $hasToken := not (empty (trim (default "" .Values.agent.token))) }}
  {{- $hasExternalSecretName := not (empty (trim (default "" .Values.agent.externalTokenSecret.name))) }}
  {{- $hasExternalSecretKey := not (empty (trim (default "" .Values.agent.externalTokenSecret.key))) }}
  {{- if and $hasExternalSecretName (not $hasExternalSecretKey) }}
    {{ fail "invalid values: when using agent.externalTokenSecret.name, agent.externalTokenSecret.key must also be set" }}
  {{- else if and $hasExternalSecretKey (not $hasExternalSecretName) }}
    {{ fail "invalid values: when using agent.externalTokenSecret.key, agent.externalTokenSecret.name must also be set" }}
  {{- else if and (not $hasToken) (not $hasExternalSecretName) }}
    {{ fail "invalid values: one of agent.token or agent.externalTokenSecret.name must be set" }}
  {{- else if and $hasToken $hasExternalSecretName }}
    {{ fail "invalid values: only one of agent.token or agent.externalTokenSecret.name can be set" }}
  {{- end }}

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
  {{- $driverName := "ebs.csi.aws.com" }}

  {{- $hasCsiDriver := false -}}
  {{- if .Capabilities.APIVersions.Has "storage.k8s.io/v1/CSIDriver" -}}
    {{- $obj := lookup "storage.k8s.io/v1" "CSIDriver" "" $driverName -}}
    {{- $hasCsiDriver = not (empty $obj) -}}
  {{- else if .Capabilities.APIVersions.Has "storage.k8s.io/v1beta1/CSIDriver" -}}
    {{- $obj := lookup "storage.k8s.io/v1beta1" "CSIDriver" "" $driverName -}}
    {{- $hasCsiDriver = not (empty $obj) -}}
  {{- end -}}

  {{- if .Values.awsEbsCsiDriver.enabled }}
    {{- if and $hasCsiDriver .Release.IsInstall }}
      {{ fail (printf "CSI driver '%s' already exists. Disable awsEbsCsiDriver.enabled or uninstall the existing CSI driver." $driverName) }}
    {{- end }}
  {{- else }}
    {{- if and .Values.ebsCsiProxy.enabled (not $hasCsiDriver) }}
      {{ fail (printf "CSI driver '%s' not found. Install it (or set awsEbsCsiDriver.enabled) or set ebsCsiProxy.enabled=false." $driverName) }}
    {{- end }}
  {{- end }}
{{- end }}
