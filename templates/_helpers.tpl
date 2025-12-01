{{/*
Return the agent image tag:
*/}}
{{- define "datafy-agent.agentImageTag" -}}
{{- (default (split "_" .Chart.AppVersion)._0 .Values.agent.image.tag) -}}
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
{{- define "datafy-agent.ebsCsiNamespace" -}}
    {{- $driverName := "ebs.csi.aws.com" -}}
    {{- $driverFound := or (not (empty (lookup "storage.k8s.io/v1" "CSIDriver" "" $driverName))) (not (empty (lookup "storage.k8s.io/v1beta1" "CSIDriver" "" $driverName))) -}}
    {{- $namespace := "" -}}
    {{- if $driverFound }}
        {{- $namespaces := lookup "v1" "Namespace" "" "" -}}
        {{- if $namespaces }}
            {{- range $ns := $namespaces.items }}
                {{- if eq $namespace "" }}
                    {{- $ds := lookup "apps/v1" "DaemonSet" $ns.metadata.name "ebs-csi-node" -}}
                    {{- if $ds }}
                        {{- $namespace = $ns.metadata.name -}}
                    {{- end -}}
                {{- end -}}
            {{- end -}}
        {{- end -}}
    {{- end -}}
    {{- $namespace -}}
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
app: datafy-agent
app.agent.version: {{ include "datafy-agent.agentImageTag" . }}
app.agent.csi.version: {{ include "datafy-agent.ebsCsiProxyImageTag" . }}
{{- end }}
{{- if .Values.extraLabels }}
{{ toYaml .Values.extraLabels }}
{{- end }}
{{- end -}}
