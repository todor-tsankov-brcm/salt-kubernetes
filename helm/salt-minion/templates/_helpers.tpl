{{/* Validation */}}
{{- define "salt-minion.validateKeyPair" -}}
{{- $minion := .Values.agent.minion -}}
{{- if ne (empty $minion.privateKeyB64) (empty $minion.publicKeyB64) -}}
{{- fail "agent.minion.privateKeyB64 and agent.minion.publicKeyB64 must be set together" -}}
{{- end -}}
{{- end -}}

{{- define "salt-minion.validateKeySource" -}}
{{- $minion := .Values.agent.minion -}}
{{- if not (or $minion.keySecretName $minion.privateKeyB64 $minion.allowSelfGeneratedKey) -}}
{{- fail "set agent.minion.keySecretName or both agent.minion.privateKeyB64 and agent.minion.publicKeyB64, or enable agent.minion.allowSelfGeneratedKey" -}}
{{- end -}}
{{- end -}}

{{/* Values */}}
{{- define "salt-minion.keySecretName" -}}
{{- .Values.agent.minion.keySecretName | default (printf "%s-keys" .Release.Name) -}}
{{- end -}}

{{/* Format an image repository and tag. */}}
{{- define "salt-minion.image" -}}
{{- printf "%s:%s" .repository (toString .tag) -}}
{{- end -}}

{{/* Resolve the minion image from chart values. */}}
{{- define "salt-minion.agentImage" -}}
{{- include "salt-minion.image" .Values.agent.image -}}
{{- end -}}

{{/* Resolve the key-generation image from chart values. */}}
{{- define "salt-minion.keygenImage" -}}
{{- include "salt-minion.image" .Values.keygen.image -}}
{{- end -}}

{{/* Enabled decisions */}}
{{- define "salt-minion.keySecretEnabled" -}}
{{- if .Values.agent.minion.privateKeyB64 -}}
true
{{- end -}}
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
