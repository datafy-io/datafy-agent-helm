
{{/*
Return the full name of the release, using fullnameOverride if set, otherwise chart name and release name
*/}}
{{- define "datafy-agent.fullname" -}}
{{- if and (hasKey .Values "fullnameOverride") (not (empty (default "" .Values.fullnameOverride))) }}
{{- default "" .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else }}
{{- printf "%s-%s" (include "datafy-agent.name" .) .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- end -}}

{{/*
Return the chart name, using nameOverride if set, otherwise .Chart.Name
*/}}
{{- define "datafy-agent.name" -}}
{{- default .Chart.Name (default "" .Values.nameOverride) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Split .Chart.AppVersion into parts separated by '+'
Example: "1.31.1+0.3.1" -> ["1.31.1", "0.3.1"]
*/}}
{{- define "datafy-agent.appVersionParts" -}}
{{- splitList "+" .Chart.AppVersion -}}
{{- end -}}

{{/*
Return the agent image tag:
use .Values.agent.image.tag if set,
otherwise take the first version (before '+') from .Chart.AppVersion
*/}}
{{- define "datafy-agent.agentImageTag" -}}
{{- if .Values.agent.image.tag }}
{{ .Values.agent.image.tag }}
{{- else }}
  {{- $parts := include "datafy-agent.appVersionParts" . | fromYamlArray -}}
  {{- index $parts 0 -}}
{{- end }}
{{- end -}}

{{/*
Return the ebsCsiProxy (k8s-csi-controller) image tag:
use .Values.ebsCsiProxy.image.tag if set,
otherwise take the first version (before '+') from .Chart.AppVersion
*/}}
{{- define "datafy-agent.ebsCsiProxyImageTag" -}}
{{- if .Values.ebsCsiProxy.image.tag }}
{{ .Values.ebsCsiProxy.image.tag }}
{{- else }}
  {{- $parts := include "datafy-agent.appVersionParts" . | fromYamlArray -}}
  {{- index $parts 1 -}}
{{- end }}
{{- end -}}

{{/*
Return selector labels for the app
*/}}
{{- define "datafy-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "datafy-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Normalize agent mode (lowercase and trimmed)
*/}}
{{- define "datafy-agent.agentModeNormalized" -}}
    {{- .Values.agent.mode | lower | trim -}}
{{- end -}}

{{/*
Determine the namespace for ebsCsiProxy: use release namespace if awsEbsCsiDriver.enabled, else .Values.ebsCsiProxy.namespace or "kube-system"
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
Common labels for all resources
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
