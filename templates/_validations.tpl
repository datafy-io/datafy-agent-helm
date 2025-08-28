{{/*
Validate that External Secrets CRDs exist when the feature is enabled
*/}}
{{- define "datafy-agent.validation.externalSecret" -}}
  {{- if .Values.agent.tokenSecret.external.remoteKey -}}
    {{- $hasV1beta1 := or
          (.Capabilities.APIVersions.Has "external-secrets.io/v1beta1/ExternalSecret")
          (.Capabilities.APIVersions.Has "external-secrets.io/v1beta1/SecretStore")
          (.Capabilities.APIVersions.Has "external-secrets.io/v1beta1/ClusterSecretStore")
        -}}
    {{- $hasV1alpha1 := or
          (.Capabilities.APIVersions.Has "external-secrets.io/v1alpha1/ExternalSecret")
          (.Capabilities.APIVersions.Has "external-secrets.io/v1alpha1/SecretStore")
          (.Capabilities.APIVersions.Has "external-secrets.io/v1alpha1/ClusterSecretStore")
        -}}
    {{- if not (or $hasV1beta1 $hasV1alpha1) -}}
      {{- fail "invalid cluster: External Secrets CRDs not found. Install external-secrets.io or remove agent.tokenSecret.external.remoteKey" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- define "datafy-agent.validation.mode" -}}
  {{- $mode := lower (trim .Values.agent.mode) -}}
  {{- if not (or (eq $mode "autoscaler") (eq $mode "sensor")) -}}
    {{- fail (printf "invalid value: agent.mode must be either 'autoscaler' or 'sensor', got '%s'" $mode) -}}
  {{- end -}}
{{- end -}}

{{- define "datafy-agent.validation.token" -}}
  {{- $token := trim (default "" .Values.agent.token) -}}
  {{- $hasToken := gt (len $token) 0 -}}
  {{- $remoteKey := trim (default "" .Values.agent.tokenSecret.external.remoteKey) -}}
  {{- $hasRemoteKey := gt (len $remoteKey) 0 -}}

  {{- if and (not $hasToken) (not $hasRemoteKey) -}}
    {{- fail "invalid values: one of agent.token or agent.tokenSecret.external.remoteKey must be set" -}}
  {{- else if and $hasToken $hasRemoteKey -}}
    {{- fail "invalid values: only one of agent.token or agent.tokenSecret.external.remoteKey can be set" -}}
  {{- else -}}
    {{- if $hasToken -}}
    {{- else if $hasRemoteKey -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
