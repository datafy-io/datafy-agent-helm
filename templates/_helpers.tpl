{{- define "ebsCsiProxyNamespace" -}}
    {{- if index .Values "aws-ebs-csi-driver" "enabled" }}
        {{- .Release.Namespace -}}
    {{- else }}
        {{- .Values.ebsCsiProxy.namespace | default "kube-system" -}}
    {{- end }}
{{- end -}}
