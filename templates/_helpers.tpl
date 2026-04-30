{{/*
Agent image tag: appVersion segment before first "_"; override with agent.image.tag.
*/}}
{{- define "datafy-agent.agentImageTag" -}}
{{- default (split "_" .Chart.AppVersion)._0 .Values.agent.image.tag -}}
{{- end -}}

{{/*
EBS CSI proxy image tag: appVersion segment after first "_"; override with ebsCsiProxy.image.tag.
*/}}
{{- define "datafy-agent.ebsCsiProxyImageTag" -}}
{{- default (split "_" .Chart.AppVersion)._1 .Values.ebsCsiProxy.image.tag -}}
{{- end -}}

{{/*
Monitor image tag: same default as sidecar (second appVersion segment); override with monitor.image.tag.
*/}}
{{- define "datafy-agent.monitorImageTag" -}}
{{- default (split "_" .Chart.AppVersion)._1 .Values.monitor.image.tag -}}
{{- end -}}

{{/*
Controller image tag: same default as sidecar (second appVersion segment); override with controller.image.tag.
*/}}
{{- define "datafy-agent.controllerImageTag" -}}
{{- default (split "_" .Chart.AppVersion)._1 .Values.controller.image.tag -}}
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
Normalized gardener mode
*/}}
{{- define "datafy-agent.gardenerModeNormalized" -}}
    {{- default "" .Values.gardener.mode | lower | trim -}}
{{- end -}}

{{/*
EBS CSI Controller Deployment name
*/}}
{{- define "datafy-agent.ebsCsiControllerDeploymentName" -}}
{{- if .Values.gardener.enabled -}}
csi-driver-controller
{{- else -}}
ebs-csi-controller
{{- end -}}
{{- end -}}

{{/*
EBS CSI Controller App name
*/}}
{{- define "datafy-agent.ebsCsiControllerAppName" -}}
{{- if .Values.gardener.enabled -}}
csi
{{- else -}}
ebs-csi-controller
{{- end -}}
{{- end -}}

{{/*
EBS CSI Node DaemonSet name
*/}}
{{- define "datafy-agent.ebsCsiNodeDaemonSetName" -}}
{{- if .Values.gardener.enabled -}}
csi-driver-node
{{- else -}}
ebs-csi-node
{{- end -}}
{{- end -}}

{{/*
EBS CSI Node App name
*/}}
{{- define "datafy-agent.ebsCsiNodeAppName" -}}
{{- if .Values.gardener.enabled -}}
csi
{{- else -}}
ebs-csi-node
{{- end -}}
{{- end -}}

{{/*
Whether extended install resources should be created.
Skip only when mode is sensor and extendedInstallOnSensor is false.
*/}}
{{- define "datafy-agent.extendedInstallEnabled" -}}
{{- $isSensor := eq (include "datafy-agent.agentModeNormalized" .) "sensor" -}}
{{- if and $isSensor (not .Values.extendedInstallOnSensor) -}}
false
{{- else -}}
true
{{- end -}}
{{- end -}}


{{/*
Whether agent should be installed
*/}}
{{- define "datafy-agent.agentInstallEnabled" -}}
{{- $isGardenerSeed := and .Values.gardener.enabled (eq (include "datafy-agent.gardenerModeNormalized" .) "seed") -}}
{{- if $isGardenerSeed -}}
false
{{- else -}}
true
{{- end -}}
{{- end -}}

{{/*
Determine ebs csi installed namespace
*/}}
{{- define "datafy-agent.ebsCsiNamespace" -}}
    {{- $driverName := "ebs.csi.aws.com" -}}
    {{- $driverFound := false -}}
    {{- if (.Capabilities.APIVersions.Has "storage.k8s.io/v1") -}}
        {{- $driverFound = not (empty (lookup "storage.k8s.io/v1" "CSIDriver" "" $driverName)) -}}
    {{- else if and (not $driverFound) (.Capabilities.APIVersions.Has "storage.k8s.io/v1beta1") -}}
        {{- $driverFound = not (empty (lookup "storage.k8s.io/v1beta1" "CSIDriver" "" $driverName)) -}}
    {{- end -}}
    {{- $namespace := "" -}}
    {{- if $driverFound }}
        {{- $namespaces := lookup "v1" "Namespace" "" "" -}}
        {{- if $namespaces }}
            {{- $nodeName := include "datafy-agent.ebsCsiNodeDaemonSetName" . -}}
            {{- range $ns := $namespaces.items }}
                {{- if eq $namespace "" }}
                    {{- $ds := lookup "apps/v1" "DaemonSet" $ns.metadata.name $nodeName -}}
                    {{- if $ds }}
                        {{- $namespace = $ds.metadata.namespace -}}
                    {{- end -}}
                {{- end -}}
            {{- end -}}
        {{- end -}}
        {{- if eq $namespace "" }}
            {{- $controllerName := include "datafy-agent.ebsCsiControllerDeploymentName" . -}}
            {{- $deployment := lookup "apps/v1" "Deployment" .Release.Namespace $controllerName -}}
            {{- if $deployment }}
                {{- $namespace = $deployment.metadata.namespace -}}
            {{- end -}}
        {{- end -}}
    {{- end -}}
    {{- $namespace -}}
{{- end -}}

{{/*
Gardener generic kubeconfig secret name
*/}}
{{- define "datafy-agent.gardenerGenericKubeconfigSecretName" -}}
{{ $genericKubeconfigSecretName := "" }}
{{- if (.Capabilities.APIVersions.Has "extensions.gardener.cloud/v1alpha1") -}}
    {{- $cluster := (lookup "extensions.gardener.cloud/v1alpha1" "Cluster" "" .Release.Namespace) -}}
    {{- if and $cluster $cluster.metadata $cluster.metadata.annotations }}
        {{- $genericKubeconfigSecretName = index $cluster.metadata.annotations "generic-token-kubeconfig.secret.gardener.cloud/name" -}}
    {{- end }}
{{- end }}
{{- $genericKubeconfigSecretName -}}
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
{{- end }}
{{- if .Values.extraLabels }}
{{ toYaml .Values.extraLabels }}
{{- end }}
{{- end -}}
