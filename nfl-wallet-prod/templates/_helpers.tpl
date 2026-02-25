{{/* Workaround: subchart nfl-wallet references nfl-wallet.partOf; ensure it's available when Argo CD/Helm renders */}}
{{- define "nfl-wallet.partOf" -}}
{{- default "nfl-wallet" ((.Values.topology | default dict).applicationName | default "nfl-wallet") | trunc 63 -}}
{{- end -}}
