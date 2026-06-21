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
Node affinity for the agent DaemonSet.
If agent.affinity is set it is used verbatim. Otherwise the default is built:
  - never schedule on denied compute types (all modes)
  - in AutoScaler mode, also exclude denied instance types (Xen / undersized nodes)
Both rules share one matchExpressions block so they AND together.
*/}}
{{- define "datafy-agent.agentAffinity" -}}
{{- if .Values.agent.affinity -}}
{{- toYaml .Values.agent.affinity -}}
{{- else -}}
{{- $isAutoscaler := eq (include "datafy-agent.agentModeNormalized" .) "autoscaler" -}}
nodeAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
      - matchExpressions:
          - key: eks.amazonaws.com/compute-type
            operator: NotIn
            values:
              - fargate
              - auto
              - hybrid
        {{- if and $isAutoscaler .Values.agent.autoScalerDeniedInstanceTypes }}
          - key: node.kubernetes.io/instance-type
            operator: NotIn
            values:
            {{- toYaml .Values.agent.autoScalerDeniedInstanceTypes | nindent 14 }}
        {{- end }}
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
Token mode: how the datafy token is provided.
  static   - inline agent.token; chart creates and owns the datafy-token secret.
  external - agent.externalTokenSecret.{name,key}; chart references an existing secret it does not own.
  role     - controller.serviceAccount.roleArn (IRSA); chart creates an empty datafy-token secret the controller populates.
  none     - nothing configured (rejected by validation).
*/}}
{{- define "datafy-agent.tokenMode" -}}
{{- $hasStatic := not (empty (trim (default "" .Values.agent.token))) -}}
{{- $hasExternal := not (empty (trim (default "" .Values.agent.externalTokenSecret.name))) -}}
{{- $hasRole := not (empty (trim (default "" .Values.controller.serviceAccount.roleArn))) -}}
{{- if $hasStatic -}}
static
{{- else if $hasExternal -}}
external
{{- else if $hasRole -}}
role
{{- else -}}
none
{{- end -}}
{{- end -}}

{{/*
Name of the secret holding the datafy token. The external secret name when one is
configured, otherwise the chart-managed "datafy-token".
*/}}
{{- define "datafy-agent.tokenSecretName" -}}
{{- default "datafy-token" .Values.agent.externalTokenSecret.name -}}
{{- end -}}

{{/*
Key within the token secret that holds the token value.
*/}}
{{- define "datafy-agent.tokenSecretKey" -}}
{{- default "token" .Values.agent.externalTokenSecret.key -}}
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
Render proxy env vars (HTTPS_PROXY/NO_PROXY plus lowercase).
*/}}
{{- define "datafy-agent.proxyEnv" -}}
{{- with .Values.proxy -}}
{{- if .httpsProxy }}
- name: HTTPS_PROXY
  value: {{ .httpsProxy | quote }}
- name: https_proxy
  value: {{ .httpsProxy | quote }}
{{- end }}
{{- if .noProxy }}
- name: NO_PROXY
  value: {{ .noProxy | quote }}
- name: no_proxy
  value: {{ .noProxy | quote }}
{{- end }}
{{- end }}
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
