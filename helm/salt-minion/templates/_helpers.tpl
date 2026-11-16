{{- define "salt-minion.validateInlineKeys" -}}
{{- if ne (empty .Values.agent.minion.privateKeyB64) (empty .Values.agent.minion.publicKeyB64) -}}
{{- fail "agent.minion.privateKeyB64 and agent.minion.publicKeyB64 must be set together" -}}
{{- end -}}
{{- end -}}
