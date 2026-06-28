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
  {{- $hasRoleArn := not (empty (trim (default "" .Values.controller.serviceAccount.roleArn))) }}
  {{- $tokenless := .Values.controller.serviceAccount.tokenless }}
  {{- $sources := 0 }}
  {{- if $hasToken }}{{- $sources = add1 $sources }}{{- end }}
  {{- if $hasExternalSecretName }}{{- $sources = add1 $sources }}{{- end }}
  {{- if $hasRoleArn }}{{- $sources = add1 $sources }}{{- end }}
  {{- if and $hasExternalSecretName (not $hasExternalSecretKey) }}
    {{ fail "invalid values: when using agent.externalTokenSecret.name, agent.externalTokenSecret.key must also be set" }}
  {{- else if and $hasExternalSecretKey (not $hasExternalSecretName) }}
    {{ fail "invalid values: when using agent.externalTokenSecret.key, agent.externalTokenSecret.name must also be set" }}
  {{- else if $tokenless }}
    {{- if gt $sources 0 }}
    {{ fail "invalid values: controller.serviceAccount.tokenless cannot be combined with a token source (agent.token, agent.externalTokenSecret, or controller.serviceAccount.roleArn); when tokenless is enabled all other token sources must be unset" }}
    {{- end }}
  {{- else if ne $sources 1 }}
    {{ fail "invalid values: exactly one token source must be set - one of agent.token, agent.externalTokenSecret, or controller.serviceAccount.roleArn (or enable controller.serviceAccount.tokenless to configure none)" }}
  {{- end }}

  {{- if $hasExternalSecretName }}
    {{- $hasExternalSecret := lookup "v1" "Secret" .Release.Namespace .Values.agent.externalTokenSecret.name }}
    {{- if not $hasExternalSecret }}
      {{ fail (printf "invalid value: external secret '%s' not found in namespace '%s'" .Values.agent.externalTokenSecret.name .Release.Namespace) }}
    {{- end }}
    {{- $ebsCsiNamespace := (include "datafy-agent.ebsCsiNamespace" . ) }}
    {{- if ne .Release.Namespace $ebsCsiNamespace }}
      {{- $hasCsiExternalSecret := lookup "v1" "Secret" $ebsCsiNamespace .Values.agent.externalTokenSecret.name }}
      {{- if not $hasCsiExternalSecret }}
        {{ fail (printf "invalid value: external secret '%s' not found in namespace '%s'" .Values.agent.externalTokenSecret.name $ebsCsiNamespace) }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
