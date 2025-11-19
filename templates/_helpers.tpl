
{{/*
Return the full name of the release, using fullnameOverride if set
*/}}
{{- define "datafy-agent.fullname" -}}
{{- if and (hasKey .Values "fullnameOverride") (not (empty (default "" .Values.fullnameOverride))) }}
{{- default "" .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else }}
  {{- $name := include "datafy-agent.name" . -}}
  {{- if eq $name .Release.Name }}
    {{- $name | trunc 63 | trimSuffix "-" -}}
  {{- else }}
    {{- printf "%s-%s" $name .Release.Name | trunc 63 | trimSuffix "-" -}}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
Return the chart name, using nameOverride if set, otherwise .Chart.Name
*/}}
{{- define "datafy-agent.name" -}}
{{- default .Chart.Name (default "" .Values.nameOverride) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Return the agent image tag:
*/}}
{{- define "datafy-agent.agentImageTag" -}}
{{- (default (split "_" .Chart.AppVersion)._2 .Values.agent.image.tag) -}}
{{- end -}}

{{/*
Return the k8s-csi-controller) image tag:
*/}}
{{- define "datafy-agent.ebsCsiProxyImageTag" -}}
{{- (default (split "_" .Chart.AppVersion)._1 .Values.ebsCsiProxy.image.tag) -}}
{{- end -}}

{{/*
Return selector labels for the app
*/}}
{{- define "datafy-agent.selectorLabels" -}}
app: datafy-agent
{{- end -}}

{{/*
Normalized agent mode
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
app: datafy-agent
app.agent.version: {{ include "datafy-agent.agentImageTag" . }}
app.agent.csi.version: {{ include "datafy-agent.ebsCsiProxyImageTag" . }}
{{- end }}
{{- if .Values.extraLabels }}
{{ toYaml .Values.extraLabels }}
{{- end }}
{{- end -}}
