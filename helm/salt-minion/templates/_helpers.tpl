{{/* Compose an image reference using the optional global or per-image registry. */}}
{{- define "salt-minion.image" -}}
{{-   $image := .image -}}
{{-   $registry := default $image.registry .global.imageRegistry | default "" | trimSuffix "/" -}}

{{-   if $registry -}}
{{-     printf "%s/%s:%v" $registry $image.repository $image.tag -}}
{{-   else -}}
{{-     printf "%s:%v" $image.repository $image.tag -}}
{{-   end -}}
{{- end -}}

{{/* Resolve the minion image from chart values. */}}
{{- define "salt-minion.agentImage" -}}
{{-   include "salt-minion.image" (dict "image" .Values.agent.image "global" .Values.global) -}}
{{- end -}}

{{/* Resolve the key-generation image from chart values. */}}
{{- define "salt-minion.keygenImage" -}}
{{-   include "salt-minion.image" (dict "image" .Values.agent.keygenImage "global" .Values.global) -}}
{{- end -}}

{{/* Validate in-cluster configuration and guard key Secret transitions. */}}
{{- define "salt-minion.validate" -}}
{{-   if eq .Values.agent.authMode "in_cluster" -}}
{{-     $keys := .Values.agent.minion -}}

{{-     range .Values.agent.extraConfigMaps -}}
{{-       if and .key (not .mountPath) -}}
{{-         fail "extraConfigMaps key requires mountPath" -}}
{{-       end -}}
{{-       if and .key (not (hasKey .data .key)) -}}
{{-         fail (printf "extraConfigMaps %s key must exist in data" .name) -}}
{{-       end -}}
{{-     end -}}

{{-     if not (hasPrefix "/" $keys.pkiDir) -}}
{{-       fail "agent.minion.pkiDir must be an absolute path" -}}
{{-     end -}}
{{-     if ne (empty $keys.privateKeyB64) (empty $keys.publicKeyB64) -}}
{{-       fail "Supply both agent.minion.privateKeyB64 and publicKeyB64" -}}
{{-     end -}}
{{-     if and $keys.keySecretName (or $keys.privateKeyB64 $keys.publicKeyB64) -}}
{{-       fail "Use either agent.minion.keySecretName or inline keys, not both" -}}
{{-     end -}}

{{-     if not $keys.privateKeyB64 -}}
{{-       $existing := lookup "v1" "Secret" .Values.namespace (include "salt-minion.keySecretName" .) -}}
{{-       if $existing -}}
{{-         $annotations := $existing.metadata.annotations | default dict -}}
{{-         if eq (index $annotations "meta.helm.sh/release-name" | default "") .Release.Name -}}
{{-           fail "Cannot switch from a Helm-managed inline key Secret directly to generated or external keys: first copy the keys to a separate existing Secret and set agent.minion.keySecretName" -}}
{{-         end -}}
{{-       end -}}
{{-     end -}}

{{-     if and .Values.agent.persistence.enabled (not (has .Values.agent.persistence.type (list "pvc" "hostPath"))) -}}
{{-       fail "agent.persistence.type must be pvc or hostPath" -}}
{{-     end -}}
{{-   end -}}
{{- end -}}

{{/* Name of the existing or release-generated key Secret. */}}
{{- define "salt-minion.keySecretName" -}}
{{-   .Values.agent.minion.keySecretName | default (printf "%s-keys" .Release.Name) -}}
{{- end -}}

{{/* Name shared by the key-generation Role and its binding. */}}
{{- define "salt-minion.keygenRoleName" -}}
{{-   printf "%s-minion-keygen-role" .Release.Name -}}
{{- end -}}

{{/* Existing or chart-created PKI claim name. */}}
{{- define "salt-minion.pkiClaimName" -}}
{{-   .Values.agent.persistence.pvc.existingClaim | default (printf "%s-pki" .Release.Name) -}}
{{- end -}}

{{/* Existing or chart-created data claim name. */}}
{{- define "salt-minion.dataClaimName" -}}
{{-   .Values.agent.dataPersistence.existingClaim | default .Values.agent.dataPersistence.claimName | default (printf "%s-data" .Release.Name) -}}
{{- end -}}

{{/* Name shared by the ClusterRole and its binding. */}}
{{- define "salt-minion.clusterRoleName" -}}
{{-   printf "%s-nodes" .Values.rbac.roleName -}}
{{- end -}}

{{/* Pod volume name for an extra ConfigMap index. */}}
{{- define "salt-minion.configVolumeName" -}}
{{-   printf "extra-config-%d" . -}}
{{- end -}}

{{/* Key Secret filenames consumed by Salt. */}}
{{- define "salt-minion.privateKeyFile" -}}
minion.pem
{{- end -}}

{{- define "salt-minion.publicKeyFile" -}}
minion.pub
{{- end -}}

{{/* Render the Job and its RBAC only when a key Secret is needed. */}}
{{- define "salt-minion.keygenJobEnabled" -}}
{{-   $agent := .Values.agent -}}
{{-   if and
        (eq $agent.authMode "in_cluster")
        (not $agent.minion.keySecretName)
        (not $agent.minion.privateKeyB64)
        (not (lookup "v1" "Secret" .Values.namespace (include "salt-minion.keySecretName" .))) -}}
true
{{-   end -}}
{{- end -}}

{{/* Create PKI storage only when persistence needs a chart-managed PVC. */}}
{{- define "salt-minion.pkiClaimEnabled" -}}
{{-   $persistence := .Values.agent.persistence -}}
{{-   if and
        (eq .Values.agent.authMode "in_cluster")
        $persistence.enabled
        (eq $persistence.type "pvc")
        (not $persistence.pvc.existingClaim) -}}
true
{{-   end -}}
{{- end -}}

{{/* Create data storage only when no existing claim is supplied. */}}
{{- define "salt-minion.dataClaimEnabled" -}}
{{-   $persistence := .Values.agent.dataPersistence -}}
{{-   if and
        (eq .Values.agent.authMode "in_cluster")
        $persistence.enabled
        (not $persistence.existingClaim) -}}
true
{{-   end -}}
{{- end -}}

{{/* Create a Secret only for an inline key pair. */}}
{{- define "salt-minion.inlineSecretEnabled" -}}
{{-   $minion := .Values.agent.minion -}}
{{-   if and
        (eq .Values.agent.authMode "in_cluster")
        $minion.privateKeyB64
        $minion.publicKeyB64 -}}
true
{{-   end -}}
{{- end -}}

{{/* Create keygen permissions only when RBAC and the Job are enabled. */}}
{{- define "salt-minion.keygenRbacEnabled" -}}
{{-   if and .Values.rbac.create (include "salt-minion.keygenJobEnabled" .) -}}
true
{{-   end -}}
{{- end -}}
