{{/*
Expand the name of the chart.
*/}}
{{- define "redis-sentinel.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "redis-sentinel.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "redis-sentinel.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "redis-sentinel.labels" -}}
helm.sh/chart: {{ include "redis-sentinel.chart" . }}
{{ include "redis-sentinel.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "redis-sentinel.selectorLabels" -}}
app.kubernetes.io/name: {{ include "redis-sentinel.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "redis-sentinel.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "redis-sentinel.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image reference: call with (dict "image" .Values.x.image "global" .Values.global)
*/}}
{{- define "redis-sentinel.image" -}}
{{- $registry := .image.registry -}}
{{- if .global.imageRegistry }}
{{- $registry = .global.imageRegistry -}}
{{- end }}
{{- printf "%s/%s:%s" $registry .image.repository .image.tag -}}
{{- end }}

{{- define "redis-sentinel.redis.image" -}}
{{- include "redis-sentinel.image" (dict "image" .Values.redis.image "global" .Values.global) -}}
{{- end }}

{{- define "redis-sentinel.sentinel.image" -}}
{{- include "redis-sentinel.image" (dict "image" .Values.sentinel.image "global" .Values.global) -}}
{{- end }}

{{- define "redis-sentinel.haproxy.image" -}}
{{- include "redis-sentinel.image" (dict "image" .Values.haproxy.image "global" .Values.global) -}}
{{- end }}

{{/*
Redis StatefulSet name; also its serviceName, so pods resolve as <pod>.<this>.<ns>.svc.<domain>
*/}}
{{- define "redis-sentinel.redis.fullname" -}}
{{- printf "%s-redis" (include "redis-sentinel.fullname" .) -}}
{{- end }}

{{- define "redis-sentinel.sentinel.fullname" -}}
{{- printf "%s-sentinel" (include "redis-sentinel.fullname" .) -}}
{{- end }}

{{/*
FQDN of a Redis pod: call with (list $ <ordinal>)
*/}}
{{- define "redis-sentinel.redis.podHost" -}}
{{- $ctx := index . 0 -}}
{{- $svc := include "redis-sentinel.redis.fullname" $ctx -}}
{{- printf "%s-%d.%s.%s.svc.%s" $svc (int (index . 1)) $svc $ctx.Release.Namespace $ctx.Values.clusterDomain -}}
{{- end }}

{{/*
Environment for the init scripts in the scripts ConfigMap
*/}}
{{- define "redis-sentinel.scriptEnv" -}}
- name: REDIS_SERVICE
  value: {{ include "redis-sentinel.redis.fullname" . }}
- name: REDIS_REPLICAS
  value: {{ .Values.redis.replicas | quote }}
- name: SENTINEL_SERVICE
  value: {{ include "redis-sentinel.sentinel.fullname" . }}
- name: SENTINEL_SERVICE_PORT
  value: {{ .Values.service.sentinel.port | quote }}
- name: SENTINEL_REPLICAS
  value: {{ .Values.sentinel.replicas | quote }}
- name: MASTER_SET
  value: {{ .Values.sentinel.masterSet | quote }}
- name: CLUSTER_DOMAIN
  value: {{ .Values.clusterDomain | quote }}
- name: NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
- name: POD_IP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
{{- if .Values.redis.auth.enabled }}
- name: REDISCLI_AUTH
  valueFrom:
    secretKeyRef:
      name: {{ include "redis-sentinel.fullname" . }}-auth
      key: redis-password
{{- end }}
{{- include "redis-sentinel.sentinel.passwordEnv" . }}
{{- end }}

{{- define "redis-sentinel.sentinel.password" -}}
{{- .Values.sentinel.auth.password | default .Values.redis.auth.password -}}
{{- end }}

{{/*
SENTINEL_PASSWORD env entry, empty when sentinel.auth is disabled
*/}}
{{- define "redis-sentinel.sentinel.passwordEnv" -}}
{{- if .Values.sentinel.auth.enabled }}
- name: SENTINEL_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "redis-sentinel.fullname" . }}-auth
      key: sentinel-password
{{- end }}
{{- end }}

{{/*
Whether HAProxy (the <fullname>-redis-dynamic master endpoint) is enabled.
service.redis.endpointController.enabled is the 1.x key and still takes precedence when set.
*/}}
{{- define "redis-sentinel.haproxy.enabled" -}}
{{- $legacy := dig "endpointController" "enabled" "unset" (.Values.service.redis | default dict) -}}
{{- if eq (toString $legacy) "unset" -}}
{{- .Values.haproxy.enabled -}}
{{- else -}}
{{- $legacy -}}
{{- end -}}
{{- end }}

{{/*
Affinity for a component: call with (dict "ctx" $ "component" "redis")
*/}}
{{- define "redis-sentinel.affinity" -}}
{{- if .ctx.Values.affinity }}
{{- toYaml .ctx.Values.affinity }}
{{- else if has .ctx.Values.podAntiAffinityPreset (list "soft" "hard") }}
{{- $term := dict "topologyKey" "kubernetes.io/hostname" "labelSelector" (dict "matchLabels" (merge (dict "app.kubernetes.io/component" .component) (include "redis-sentinel.selectorLabels" .ctx | fromYaml))) }}
podAntiAffinity:
{{- if eq .ctx.Values.podAntiAffinityPreset "hard" }}
  requiredDuringSchedulingIgnoredDuringExecution:
  {{- toYaml (list $term) | nindent 2 }}
{{- else }}
  preferredDuringSchedulingIgnoredDuringExecution:
  {{- toYaml (list (dict "weight" 100 "podAffinityTerm" $term)) | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Fail early on values from chart 1.x that no longer apply
*/}}
{{- define "redis-sentinel.validate" -}}
{{- if or .Values.redis.master .Values.redis.replica }}
{{- fail "redis.master and redis.replica were removed in chart 2.0.0: use redis.replicas (total number of Redis pods). See the upgrade notes in README.md." }}
{{- end }}
{{- if gt (int .Values.sentinel.quorum) (int .Values.sentinel.replicas) }}
{{- fail "sentinel.quorum must not be greater than sentinel.replicas" }}
{{- end }}
{{- if and .Values.redis.auth.enabled (not .Values.redis.auth.password) }}
{{- fail "redis.auth.password is required when redis.auth.enabled is true" }}
{{- end }}
{{- if and .Values.sentinel.auth.enabled (not (include "redis-sentinel.sentinel.password" .)) }}
{{- fail "sentinel.auth.enabled needs sentinel.auth.password (or redis.auth.password)" }}
{{- end }}
{{- /* passwords are appended from the Secret and win over these lines, so a different value would silently change the password */}}
{{- range $key := list "requirepass" "masterauth" }}
{{- $line := regexFind (printf "(?m)^\\s*%s\\s+\\S+" $key) $.Values.redis.configuration }}
{{- if $line }}
{{- $value := regexReplaceAll (printf "^\\s*%s\\s+" $key) $line "" | trimAll "\"'" }}
{{- if or (not $.Values.redis.auth.enabled) (ne $value (toString $.Values.redis.auth.password)) }}
{{- fail (printf "redis.configuration sets %s, which differs from redis.auth: remove it from redis.configuration, the chart sets it from redis.auth.password" $key) }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
