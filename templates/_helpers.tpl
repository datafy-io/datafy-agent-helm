{{/*
Normolized agent mode
*/}}
{{- define "datafy-agent.agentModeNormalized" -}}
    {{- .Values.agent.mode | lower | trim -}}
{{- end -}}

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
