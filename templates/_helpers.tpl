{{/*
Determine ebs csi installed namespace
*/}}
{{- define "datafy-agent.ebsCsiProxyNamespace" -}}
    {{- if .Values.awsEbsCsiDriver.enabled }}
        {{- .Release.Namespace -}}
    {{- else }}
        {{- .Values.ebsCsiProxy.namespace | default "kube-system" -}}
    {{- end }}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "datafy-agent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "datafy-agent.labels" -}}
{{- if ne .Release.Name "kustomize" -}}
helm.sh/chart: {{ include "datafy-agent.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/component: datafy-agent
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
{{- if .Values.extraLabels }}
{{ toYaml .Values.extraLabels }}
{{- end }}
{{- end -}}

{{/*
  Builds a single-line string of env variables for datafy-agent-installer:
  "FOO=bar BAZ=qux ..."
*/}}
{{- define "agent.extraInstallEnv" -}}
{{- $env := dict -}}
{{- if eq .Values.agent.skipStartAgent true }}
    {{- $_ := set $env "SKIP_START_AGENT" "true" }}
{{- end }}
{{- if eq .Values.agent.skipInstallCore true }}
    {{- $_ := set $env "SKIP_INSTALL_CORE" "true" }}
{{- end }}
{{- if eq .Values.agent.mode "Sensor" }}
    {{- $_ := set $env "DISCOVERY_ONLY" "true" }}
{{- end }}
{{- if eq .Values.agent.k8sCsiEnabled false }}
    {{- $_ := set $env "DISABLE_K8S_CSI" "true" }}
{{- end }}
{{- if eq .Values.agent.coreMockEnabled true }}
    {{- $_ := set $env "ENABLE_CORE_MOCK" "true" }}
{{- end }}
{{- if eq .Values.agent.hqMockEnabled true }}
    {{- $_ := set $env "ENABLE_HQ_MOCK" "true" }}
{{- end }}
{{- range $key, $val := $env }}
- name: {{ $key }}
  value: {{ $val | quote }}
{{- end }}
{{- end }}
