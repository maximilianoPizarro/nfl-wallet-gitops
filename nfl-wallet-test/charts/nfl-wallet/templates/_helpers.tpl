{{/*
Full image name for a component
*/}}
{{- define "nfl-wallet.image" -}}
{{- $ns := .root.Values.imageNamespace -}}
{{- $reg := default "quay.io" .root.Values.global.imageRegistry -}}
{{- printf "%s/%s/%s:%s" $reg $ns .image .tag -}}
{{- end -}}

{{- define "nfl-wallet.fullname" -}}
{{- printf "%s-%s" (include "nfl-wallet.releaseName" .) .component -}}
{{- end -}}

{{- define "nfl-wallet.releaseName" -}}
{{- default .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Application name for topology grouping (app.kubernetes.io/part-of) */}}
{{- define "nfl-wallet.partOf" -}}
{{- default "nfl-wallet" .Values.topology.applicationName | trunc 63 -}}
{{- end -}}

{{/* True if AuthorizationPolicy should be created for this API (handles --set string "true"/"false"). Call with: include "nfl-wallet.authPolicy.requireFor" (dict "root" . "key" "requireForRaiders") */}}
{{- define "nfl-wallet.authPolicy.requireFor" -}}
{{- $root := .root -}}
{{- $ap := $root.Values.authorizationPolicy | default dict -}}
{{- $v := index $ap .key -}}
{{- $vStr := printf "%v" $v -}}
{{- if not $ap.enabled -}}
false
{{- else if eq $v false -}}
false
{{- else if eq $vStr "false" -}}
false
{{- else -}}
true
{{- end -}}
{{- end -}}
