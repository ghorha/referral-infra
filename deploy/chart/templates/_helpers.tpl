{{/*
Chart name (app.kubernetes.io/name). Same for every release by design; the
per-release identity comes from app.kubernetes.io/instance = release name.
*/}}
{{- define "referral-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully-qualified object name. Normally this is just the release name, which the
deploy convention sets to referral-<svc> (referral-auth-service, referral-listing-service, ...). That name is
what other services resolve via in-cluster DNS, so it MUST equal referral-<svc>.
*/}}
{{- define "referral-service.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "referral-service.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "referral-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: referral
{{- end -}}

{{/*
Selector labels — instance makes the selector unique per service/release.
*/}}
{{- define "referral-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "referral-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
ServiceAccount name to use.
*/}}
{{- define "referral-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "referral-service.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Fully-qualified image reference. Registry is optional so the chart still renders
without it (e.g. dry-run), but a real deploy always supplies image.registry.
*/}}
{{- define "referral-service.image" -}}
{{- $registry := .Values.image.registry | trimSuffix "/" -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry .Values.image.repository (.Values.image.tag | toString) -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | toString) -}}
{{- end -}}
{{- end -}}
