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
Instance types the agent must not be scheduled on in AutoScaler mode.
These are the Xen-based / previous-generation instances (no Nitro hypervisor
label exists on managed node groups, so they are enumerated). Nitro equivalents
(e.g. i3en, i4i, m5, c5, r5 and newer) are intentionally absent and stay eligible.
This is a chart-enforced invariant and is intentionally not exposed as a value.
*/}}
{{- define "datafy-agent.autoScalerDeniedInstanceTypes" -}}
- m1.small
- m1.medium
- m1.large
- m1.xlarge
- m2.xlarge
- m2.2xlarge
- m2.4xlarge
- m3.medium
- m3.large
- m3.xlarge
- m3.2xlarge
- m4.large
- m4.xlarge
- m4.2xlarge
- m4.4xlarge
- m4.10xlarge
- m4.16xlarge
- t1.micro
- t2.nano
- t2.micro
- t2.small
- t2.medium
- t2.large
- t2.xlarge
- t2.2xlarge
- c1.medium
- c1.xlarge
- c3.large
- c3.xlarge
- c3.2xlarge
- c3.4xlarge
- c3.8xlarge
- c4.large
- c4.xlarge
- c4.2xlarge
- c4.4xlarge
- c4.8xlarge
- r3.large
- r3.xlarge
- r3.2xlarge
- r3.4xlarge
- r3.8xlarge
- r4.large
- r4.xlarge
- r4.2xlarge
- r4.4xlarge
- r4.8xlarge
- r4.16xlarge
- x1.16xlarge
- x1.32xlarge
- x1e.xlarge
- x1e.2xlarge
- x1e.4xlarge
- x1e.8xlarge
- x1e.16xlarge
- x1e.32xlarge
- d2.xlarge
- d2.2xlarge
- d2.4xlarge
- d2.8xlarge
- h1.2xlarge
- h1.4xlarge
- h1.8xlarge
- h1.16xlarge
- i2.xlarge
- i2.2xlarge
- i2.4xlarge
- i2.8xlarge
- i3.large
- i3.xlarge
- i3.2xlarge
- i3.4xlarge
- i3.8xlarge
- i3.16xlarge
- g3.4xlarge
- g3.8xlarge
- g3.16xlarge
- g3s.xlarge
- p3.2xlarge
- p3.8xlarge
- p3.16xlarge
{{- end -}}

{{/*
Node affinity for the agent DaemonSet.
The chart enforces non-overridable node-affinity rules:
  - never schedule on denied compute types: fargate, auto, hybrid (all modes)
  - in AutoScaler mode, also exclude denied instance types (Xen / previous-gen)
These required matchExpressions are ANDed into the affinity. A customer-supplied
agent.affinity is merged on top (it can only further restrict): its pod (anti-)
affinity is preserved, and the enforced expressions are injected into every
nodeSelectorTerm. Note nodeSelectorTerms are ORed by Kubernetes, so injecting
into each term (rather than adding a sibling term) is what preserves the AND.
*/}}
{{- define "datafy-agent.agentAffinity" -}}
{{- $isAutoscaler := eq (include "datafy-agent.agentModeNormalized" .) "autoscaler" -}}
{{- $enforced := list (dict "key" "eks.amazonaws.com/compute-type" "operator" "NotIn" "values" (list "fargate" "auto" "hybrid")) -}}
{{- if $isAutoscaler -}}
{{- $deniedInstanceTypes := include "datafy-agent.autoScalerDeniedInstanceTypes" . | fromYamlArray -}}
{{- $enforced = append $enforced (dict "key" "node.kubernetes.io/instance-type" "operator" "NotIn" "values" $deniedInstanceTypes) -}}
{{- end -}}
{{- $affinity := deepCopy (default (dict) .Values.agent.affinity) -}}
{{- $nodeAffinity := default (dict) $affinity.nodeAffinity -}}
{{- $required := default (dict) $nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution -}}
{{- $terms := default (list) $required.nodeSelectorTerms -}}
{{- if not $terms -}}
{{- $terms = list (dict "matchExpressions" (list)) -}}
{{- end -}}
{{- $mergedTerms := list -}}
{{- range $term := $terms -}}
{{- $term = set $term "matchExpressions" (concat (default (list) $term.matchExpressions) $enforced) -}}
{{- $mergedTerms = append $mergedTerms $term -}}
{{- end -}}
{{- $required = set $required "nodeSelectorTerms" $mergedTerms -}}
{{- $nodeAffinity = set $nodeAffinity "requiredDuringSchedulingIgnoredDuringExecution" $required -}}
{{- $affinity = set $affinity "nodeAffinity" $nodeAffinity -}}
{{- toYaml $affinity -}}
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
