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
