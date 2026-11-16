{{- define "salt-minion.validateInlineKeys" -}}
{{- $minion := .Values.agent.minion -}}
{{- if ne (empty $minion.privateKeyB64) (empty $minion.publicKeyB64) -}}
{{- fail "agent.minion.privateKeyB64 and agent.minion.publicKeyB64 must be set together" -}}
{{- end -}}
{{- end -}}

{{- define "salt-minion.keySecretName" -}}
{{- .Values.agent.minion.keySecretName | default (printf "%s-keys" .Release.Name) -}}
{{- end -}}

{{- define "salt-minion.keygenEnabled" -}}
{{- $minion := .Values.agent.minion -}}
{{- if and (eq .Values.agent.authMode "in_cluster") $minion.allowSelfGeneratedKey (not $minion.keySecretName) (not $minion.privateKeyB64) -}}
true
{{- end -}}
{{- end -}}

{{- define "salt-minion.keygenJobEnabled" -}}
{{- if include "salt-minion.keygenEnabled" . -}}
{{- $secretName := include "salt-minion.keySecretName" . -}}
{{- if not (lookup "v1" "Secret" .Values.namespace $secretName) -}}
true
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "salt-minion.keygenRbacEnabled" -}}
{{- if and .Values.rbac.create (include "salt-minion.keygenEnabled" .) -}}
true
{{- end -}}
{{- end -}}

{{- define "salt-minion.validateKeySource" -}}
{{- $minion := .Values.agent.minion -}}
{{- if not (or $minion.keySecretName $minion.privateKeyB64 $minion.allowSelfGeneratedKey) -}}
{{- fail "set agent.minion.keySecretName or inline keys, or enable agent.minion.allowSelfGeneratedKey" -}}
{{- end -}}
{{- end -}}
