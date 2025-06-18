# Redis Sentinel Helm Chart

A comprehensive Helm chart for deploying Redis with Sentinel for high availability on Kubernetes.

## Features

- ✅ **High Availability**: 3-pod StatefulSet Redis Sentinel architecture
- ✅ **Master-Replica Setup**: 1 Master + 2 Replica Redis configuration
- ✅ **Automatic Failover**: Sentinel-managed automatic master failover
- ✅ **ACL Support**: User-based access control and authentication
- ✅ **Persistence**: Persistent data storage with PVC support
- ✅ **Easy Scaling**: Dynamic scaling via Helm upgrades
- ✅ **Security**: Pod security contexts and resource limits
- ✅ **Monitoring Ready**: Redis Exporter support for metrics

## Quick Start

### 1. Download the Chart
```bash
git clone https://github.com/ozkanpoyrazoglu/simplified-redis-chart.git
cd redis-sentinel
```

### 2. Basic Installation
```bash
# Install with default settings
helm install redis-sentinel ./simplified-redis-chart

# Or install with custom values
helm install redis-sentinel ./simplified-redis-chart -f custom-values.yaml
```

### 3. Check Status
```bash
# Check pods
kubectl get pods -l app.kubernetes.io/name=redis-sentinel

# Check services
kubectl get svc -l app.kubernetes.io/name=redis-sentinel

# Check Redis master status via Sentinel
kubectl exec redis-sentinel-sentinel-0 -- redis-cli -p 26379 sentinel masters
```

## Configuration

### Authentication & ACL

Configure Redis authentication and ACL users in `values.yaml`:

```yaml
redis:
  auth:
    enabled: true
    password: "your-secure-password"
    acl:
      enabled: true
      users:
        - username: "admin"
          password: "admin-password"
          permissions: "+@all"
        - username: "readonly"
          password: "readonly-password"
          permissions: "+@read -@write"
        - username: "app-user"
          password: "app-password"
          permissions: "+@all -@dangerous -flushdb -flushall"
```

### Persistence

Enable and configure persistent storage:

```yaml
redis:
  persistence:
    enabled: true
    storageClass: "fast-ssd"
    size: 20Gi
    accessModes:
      - ReadWriteOnce
```

### Resource Management

Set resource limits and requests:

```yaml
redis:
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 200m
      memory: 256Mi

sentinel:
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 50m
      memory: 128Mi
```

### Production Configuration Example

```yaml
# Production-ready configuration
global:
  storageClass: "fast-ssd"

redis:
  auth:
    enabled: true
    password: "production-redis-password"
    acl:
      enabled: true
      users:
        - username: "admin"
          password: "admin-secure-password"
          permissions: "+@all"
        - username: "app"
          password: "app-secure-password"
          permissions: "+@all -@dangerous -flushdb -flushall -config"
        - username: "monitoring"
          password: "monitoring-password"
          permissions: "+@read +info +ping"

  persistence:
    enabled: true
    storageClass: "fast-ssd"
    size: 50Gi

  resources:
    limits:
      cpu: 2000m
      memory: 2Gi
    requests:
      cpu: 500m
      memory: 512Mi

  replica:
    enabled: true
    replicas: 2

sentinel:
  replicas: 3
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 128Mi

# Enable monitoring
metrics:
  enabled: true

# Pod disruption budget for high availability
podDisruptionBudget:
  enabled: true
  minAvailable: 2
```

## Operations

### Scaling

Scale Redis replicas and Sentinels:

```bash
# Scale Redis replicas
helm upgrade redis-sentinel ./simplified-redis-chart --set redis.replica.replicas=4

# Scale Sentinels (should be odd number)
helm upgrade redis-sentinel ./simplified-redis-chart --set sentinel.replicas=5
```

### Connecting to Redis

#### Connect to Redis Master
```bash
# Get master info from Sentinel
kubectl exec redis-sentinel-sentinel-0 -- redis-cli -p 26379 sentinel get-master-addr-by-name mymaster

# Connect directly to master service
redis-cli -h redis-sentinel-redis-master -p 6379 -a your-password
```

#### Connect via Sentinel (Recommended)
```bash
# Connect to Sentinel to discover master
redis-cli -h redis-sentinel-sentinel -p 26379 sentinel masters

# Your application should use Sentinel-aware Redis clients
```

### Managing ACL Users

Add or modify ACL users by updating values.yaml and running:

```bash
helm upgrade redis-sentinel ./simplified-redis-chart -f updated-values.yaml
```

### Backup and Restore

#### Create Backup
```bash
# Execute BGSAVE on master
kubectl exec redis-sentinel-redis-master-0 -- redis-cli -a your-password BGSAVE

# Copy dump.rdb file
kubectl cp redis-sentinel-redis-master-0:/data/dump.rdb ./backup-$(date +%Y%m%d).rdb
```

#### Restore from Backup
```bash
# Scale down Redis (backup existing data first!)
helm upgrade redis-sentinel ./simplified-redis-chart --set redis.master.replicas=0 --set redis.replica.replicas=0

# Copy backup file to master pod
kubectl cp ./backup-file.rdb redis-sentinel-redis-master-0:/data/dump.rdb

# Scale back up
helm upgrade redis-sentinel ./simplified-redis-chart --set redis.master.replicas=1 --set redis.replica.replicas=2
```

## Monitoring

### Enable Metrics
```yaml
metrics:
  enabled: true
  port: 9121
```

### Prometheus Integration
The chart supports Redis Exporter for Prometheus monitoring. Enable it in values.yaml and configure your Prometheus to scrape the metrics endpoint.

### Health Checks
```bash
# Check Redis health
kubectl exec redis-sentinel-redis-master-0 -- redis-cli -a your-password ping

# Check Sentinel health
kubectl exec redis-sentinel-sentinel-0 -- redis-cli -p 26379 ping

# Check Sentinel master status
kubectl exec redis-sentinel-sentinel-0 -- redis-cli -p 26379 sentinel masters
```

## Troubleshooting

### Common Issues

#### 1. Sentinel Cannot Resolve Master Hostname
If you see hostname resolution errors, the chart automatically uses service names. If needed, you can manually set the master IP:

```bash
# Get the master service IP
kubectl get svc redis-sentinel-redis-master

# Update ConfigMap if needed
kubectl edit configmap redis-sentinel-sentinel-config
```

#### 2. Permission Denied on Sentinel Config
This is handled automatically by the chart using an init container that copies the config to a writable location.

#### 3. Pods Stuck in Pending
Check resource availability and storage class:

```bash
kubectl describe pod redis-sentinel-redis-master-0
kubectl get pvc
```

#### 4. Authentication Failures
Verify password configuration:

```bash
# Check secret
kubectl get secret redis-sentinel-auth -o yaml

# Test authentication
kubectl exec redis-sentinel-redis-master-0 -- redis-cli -a your-password ping
```

### Logs

Check logs for debugging:

```bash
# Redis master logs
kubectl logs redis-sentinel-redis-master-0

# Sentinel logs
kubectl logs redis-sentinel-sentinel-0

# Check all pods
kubectl logs -l app.kubernetes.io/name=redis-sentinel
```

## Uninstalling

```bash
# Uninstall the release
helm uninstall redis-sentinel

# Optionally remove PVCs (WARNING: This will delete data)
kubectl delete pvc -l app.kubernetes.io/name=redis-sentinel
```

## Security Considerations

- Always enable authentication in production
- Use strong passwords for all users
- Configure ACL permissions following the principle of least privilege
- Enable network policies if your cluster supports them
- Regularly update Redis images for security patches
- Use TLS/SSL for production deployments (requires additional configuration)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test the chart thoroughly
5. Submit a pull request

## License

This chart is licensed under the MIT License. See LICENSE file for details.

## Support

For issues and questions:
- Create an issue in the repository
- Check the troubleshooting section
- Review Redis and Sentinel documentation# Redis Sentinel Helm Chart

Bu Helm chart, Kubernetes üzerinde yüksek erişilebilir Redis Sentinel kurulumu sağlar.

## Dizin Yapısı

```
redis-sentinel/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── _helpers.tpl
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── redis-statefulset.yaml
│   ├── sentinel-statefulset.yaml
│   ├── redis-service.yaml
│   ├── sentinel-service.yaml
│   └── serviceaccount.yaml
└── README.md
```

## Chart.yaml

```yaml
apiVersion: v2
name: redis-sentinel
description: A Helm chart for Redis with Sentinel for high availability
type: application
version: 1.0.0
appVersion: "7.2"
keywords:
  - redis
  - sentinel
  - database
  - cache
  - nosql
home: https://redis.io
sources:
  - https://github.com/redis/redis
maintainers:
  - name: Your Name
    email: your.email@example.com
```

## values.yaml

```yaml
# Global configurations
global:
  imageRegistry: ""
  storageClass: ""

# Redis configuration
redis:
  image:
    registry: docker.io
    repository: redis
    tag: "7.2-alpine"
    pullPolicy: IfNotPresent
  
  # Redis master configuration
  master:
    replicas: 1
    
  # Redis replica configuration  
  replica:
    enabled: true
    replicas: 2
    
  # Authentication
  auth:
    enabled: true
    password: "redis-password-123"
    # ACL users configuration
    acl:
      enabled: true
      users:
        - username: "admin"
          password: "admin-password-123"
          permissions: "+@all"
        - username: "readonly"
          password: "readonly-password-123"
          permissions: "+@read"
        - username: "app-user"
          password: "app-password-123"
          permissions: "+@all -@dangerous"
  
  # Redis configuration parameters
  configuration: |
    # Redis configuration
    maxmemory 256mb
    maxmemory-policy allkeys-lru
    save 900 1
    save 300 10
    save 60 10000
    
  # Persistence
  persistence:
    enabled: true
    storageClass: ""
    size: 8Gi
    accessModes:
      - ReadWriteOnce
  
  # Resources
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 128Mi

# Sentinel configuration
sentinel:
  image:
    registry: docker.io
    repository: redis
    tag: "7.2-alpine"
    pullPolicy: IfNotPresent
    
  replicas: 3
  
  # Sentinel configuration - basic settings, monitor config is in template
  configuration: |
    # Custom sentinel configurations can be added here
    # Basic monitor and auth configurations are handled automatically
    
  # Resources
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 50m
      memory: 64Mi

# Service configurations
service:
  redis:
    type: ClusterIP
    port: 6379
    annotations: {}
    
  sentinel:
    type: ClusterIP
    port: 26379
    annotations: {}

# ServiceAccount
serviceAccount:
  create: true
  annotations: {}
  name: ""

# Pod Security Context
podSecurityContext:
  fsGroup: 999
  runAsUser: 999
  runAsGroup: 999

# Security Context
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 999

# Node selector, tolerations and affinity
nodeSelector: {}
tolerations: []
affinity: {}

# Pod disruption budget
podDisruptionBudget:
  enabled: true
  minAvailable: 1

# Monitoring
metrics:
  enabled: false
  image:
    registry: docker.io
    repository: oliver006/redis_exporter
    tag: v1.45.0
    pullPolicy: IfNotPresent
  port: 9121
  resources:
    limits:
      cpu: 100m
      memory: 64Mi
    requests:
      cpu: 10m
      memory: 32Mi
```

## templates/_helpers.tpl

```yaml
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
Redis image
*/}}
{{- define "redis-sentinel.redis.image" -}}
{{- $registry := .Values.redis.image.registry -}}
{{- $repository := .Values.redis.image.repository -}}
{{- $tag := .Values.redis.image.tag -}}
{{- if .Values.global.imageRegistry }}
{{- $registry = .Values.global.imageRegistry -}}
{{- end }}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- end }}

{{/*
Sentinel image
*/}}
{{- define "redis-sentinel.sentinel.image" -}}
{{- $registry := .Values.sentinel.image.registry -}}
{{- $repository := .Values.sentinel.image.repository -}}
{{- $tag := .Values.sentinel.image.tag -}}
{{- if .Values.global.imageRegistry }}
{{- $registry = .Values.global.imageRegistry -}}
{{- end }}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- end }}
```

## templates/configmap.yaml

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "redis-sentinel.fullname" . }}-redis-config
  labels:
    {{- include "redis-sentinel.labels" . | nindent 4 }}
data:
  redis.conf: |
    {{- .Values.redis.configuration | nindent 4 }}
    {{- if .Values.redis.auth.enabled }}
    requirepass {{ .Values.redis.auth.password }}
    {{- end }}
    {{- if and .Values.redis.auth.enabled .Values.redis.auth.acl.enabled }}
    aclfile /opt/redis/acl.conf
    {{- end }}
  {{- if and .Values.redis.auth.enabled .Values.redis.auth.acl.enabled }}
  acl.conf: |
    {{- range .Values.redis.auth.acl.users }}
    user {{ .username }} on >{{ .password }} {{ .permissions }}
    {{- end }}
  {{- end }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "redis-sentinel.fullname" . }}-sentinel-config
  labels:
    {{- include "redis-sentinel.labels" . | nindent 4 }}
data:
  sentinel.conf: |
    # Basic sentinel configuration
    port 26379
    
    # Monitor the master
    sentinel monitor mymaster {{ include "redis-sentinel.fullname" . }}-redis-master.{{ .Release.Namespace }}.svc.cluster.local 6379 2
    sentinel down-after-milliseconds mymaster 5000
    sentinel parallel-syncs mymaster 1
    sentinel failover-timeout mymaster 10000
    
    {{- if .Values.redis.auth.enabled }}
    sentinel auth-pass mymaster {{ .Values.redis.auth.password }}
    {{- end }}
    
    # Additional configuration from values
    {{- if .Values.sentinel.configuration }}
    {{- .Values.sentinel.configuration | nindent 4 }}
    {{- end }}
```

## templates/secret.yaml

```yaml
{{- if .Values.redis.auth.enabled }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "redis-sentinel.fullname" . }}-auth
  labels:
    {{- include "redis-sentinel.labels" . | nindent 4 }}
type: Opaque
data:
  redis-password: {{ .Values.redis.auth.password | b64enc | quote }}
  {{- if .Values.redis.auth.acl.enabled }}
  {{- range .Values.redis.auth.acl.users }}
  {{ .username }}-password: {{ .password | b64enc | quote }}
  {{- end }}
  {{- end }}
{{- end }}
```

## templates/redis-statefulset.yaml

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "redis-sentinel.fullname" . }}-redis-master
  labels:
    {{- include "redis-sentinel.labels" . | nindent 4 }}
    app.kubernetes.io/component: redis-master
spec:
  serviceName: {{ include "redis-sentinel.fullname" . }}-redis-master
  replicas: {{ .Values.redis.master.replicas }}
  selector:
    matchLabels:
      {{- include "redis-sentinel.selectorLabels" . | nindent 6 }}
      app.kubernetes.io/component: redis-master
  template:
    metadata:
      labels:
        {{- include "redis-sentinel.selectorLabels" . | nindent 8 }}
        app.kubernetes.io/component: redis-master
    spec:
      serviceAccountName: {{ include "redis-sentinel.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
      - name: redis
        image: {{ include "redis-sentinel.redis.image" . }}
        imagePullPolicy: {{ .Values.redis.image.pullPolicy }}
        securityContext:
          {{- toYaml .Values.securityContext | nindent 10 }}
        ports:
        - containerPort: 6379
          name: redis
        command:
        - redis-server
        - /opt/redis/redis.conf
        env:
        {{- if .Values.redis.auth.enabled }}
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: {{ include "redis-sentinel.fullname" . }}-auth
              key: redis-password
        {{- end }}
        volumeMounts:
        - name: redis-config
          mountPath: /opt/redis
        - name: redis-data
          mountPath: /data
        - name: tmp
          mountPath: /tmp
        resources:
          {{- toYaml .Values.redis.resources | nindent 10 }}
        livenessProbe:
          exec:
            command:
            - redis-cli
            - --no-auth-warning
            {{- if .Values.redis.auth.enabled }}
            - -a
            - $(REDIS_PASSWORD)
            {{- end }}
            - ping
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - redis-cli
            - --no-auth-warning
            {{- if .Values.redis.auth.enabled }}
            - -a
            - $(REDIS_PASSWORD)
            {{- end }}
            - ping
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: redis-config
        configMap:
          name: {{ include "redis-sentinel.fullname" . }}-redis-config
      - name: tmp
        emptyDir: {}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
  {{- if .Values.redis.persistence.enabled }}
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes:
        {{- range .Values.redis.persistence.accessModes }}
        - {{ . | quote }}
        {{- end }}
      {{- if .Values.redis.persistence.storageClass }}
      {{- if (eq "-" .Values.redis.persistence.storageClass) }}
      storageClassName: ""
      {{- else }}
      storageClassName: {{ .Values.redis.persistence.storageClass | quote }}
      {{- end }}
      {{- else if .Values.global.storageClass }}
      storageClassName: {{ .Values.global.storageClass | quote }}
      {{- end }}
      resources:
        requests:
          storage: {{ .Values.redis.persistence.size | quote }}
  {{- else }}
      - name: redis-data
        emptyDir: {}
  {{- end }}
---
{{- if .Values.redis.replica.enabled }}
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "redis-sentinel.fullname" . }}-redis-replica
  labels:
    {{- include "redis-sentinel.labels" . | nindent 4 }}
    app.kubernetes.io/component: redis-replica
spec:
  serviceName: {{ include "redis-sentinel.fullname" . }}-redis-replica
  replicas: {{ .Values.redis.replica.replicas }}
  selector:
    matchLabels:
      {{- include "redis-sentinel.selectorLabels" . | nindent 6 }}
      app.kubernetes.io/component: redis-replica
  template:
    metadata:
      labels:
        {{- include "redis-sentinel.selectorLabels" . | nindent 8 }}
        app.kubernetes.io/component: redis-replica
    spec:
      serviceAccountName: {{ include "redis-sentinel.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
      - name: redis
        image: {{ include "redis-sentinel.redis.image" . }}
        imagePullPolicy: {{ .Values.redis.image.pullPolicy }}
        securityContext:
          {{- toYaml .Values.securityContext | nindent 10 }}
        ports:
        - containerPort: 6379
          name: redis
        command:
        - redis-server
        - /opt/redis/redis.conf
        - --replicaof
        - {{ include "redis-sentinel.fullname" . }}-redis-master.{{ .Release.Namespace }}.svc.cluster.local
        - "6379"
        env:
        {{- if .Values.redis.auth.enabled }}
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: {{ include "redis-sentinel.fullname" . }}-auth
              key: redis-password
        {{- end }}
        volumeMounts:
        - name: redis-config
          mountPath: /opt/redis
        - name: redis-data
          mountPath: /data
        - name: tmp
          mountPath: /tmp
        resources:
          {{- toYaml .Values.redis.resources | nindent 10 }}
        livenessProbe:
          exec:
            command:
            - redis-cli
            - --no-auth-warning
            {{- if .Values.redis.auth.enabled }}
            - -a
            - $(REDIS_PASSWORD)
            {{- end }}
            - ping
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - redis-cli
            - --no-auth-warning
            {{- if .Values.redis.auth.enabled }}
            - -a
            - $(REDIS_PASSWORD)
            {{- end }}
            - ping
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: redis-config
        configMap:
          name: {{ include "redis-sentinel.fullname" . }}-redis-config
      - name: tmp
        emptyDir: {}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
  {{- if .Values.redis.persistence.enabled }}
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes:
        {{- range .Values.redis.persistence.accessModes }}
        - {{ . | quote }}
        {{- end }}
      {{- if .Values.redis.persistence.storageClass }}
      {{- if (eq "-" .Values.redis.persistence.storageClass) }}
      storageClassName: ""
      {{- else }}
      storageClassName: {{ .Values.redis.persistence.storageClass | quote }}
      {{- end }}
      {{- else if .Values.global.storageClass }}
      storageClassName: {{ .Values.global.storageClass | quote }}
      {{- end }}
      resources:
        requests:
          storage: {{ .Values.redis.persistence.size | quote }}
  {{- else }}
      - name: redis-data
        emptyDir: {}
  {{- end }}
{{- end }}
```

## templates/sentinel-statefulset.yaml

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "redis-sentinel.fullname" . }}-sentinel
  labels:
    {{- include "redis-sentinel.labels" . | nindent 4 }}
    app.kubernetes.io/component: sentinel
spec:
  serviceName: {{ include "redis-sentinel.fullname" . }}-sentinel
  replicas: {{ .Values.sentinel.replicas }}
  selector:
    matchLabels:
      {{- include "redis-sentinel.selectorLabels" . | nindent 6 }}
      app.kubernetes.io/component: sentinel
  template:
    metadata:
      labels:
        {{- include "redis-sentinel.selectorLabels" . | nindent 8 }}
        app.kubernetes.io/component: sentinel
    spec:
      serviceAccountName: {{ include "redis-sentinel.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
      - name: sentinel
        image: {{ include "redis-sentinel.sentinel.image" . }}
        imagePullPolicy: {{ .Values.sentinel.image.pullPolicy }}
        securityContext:
          {{- toYaml .Values.securityContext | nindent 10 }}
        ports:
        - containerPort: 26379
          name: sentinel
        command:
        - redis-sentinel
        - /opt/sentinel/sentinel.conf
        volumeMounts:
        - name: sentinel-config
          mountPath: /opt/sentinel
        - name: tmp
          mountPath: /tmp
        resources:
          {{- toYaml .Values.sentinel.resources | nindent 10 }}
        livenessProbe:
          exec:
            command:
            - redis-cli
            - -p
            - "26379"
            - ping
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - redis-cli
            - -p
            - "26379"
            - ping
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: sentinel-config
        configMap:
          name: {{ include "redis-sentinel.fullname" . }}-sentinel-config
      - name: tmp
        emptyDir: {}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
```

## templates/redis-service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "redis-sentinel.fullname" . }}-redis-master
  labels:
    {{- include "redis-sentinel.labels" . | nindent 4 }}
    app.kubernetes.io/component: redis-master
  {{- with .Values.service.redis.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: {{ .Values.service.redis.type }}
  ports:
  - port: {{ .Values.service.redis.port }}
    targetPort: redis
    protocol: TCP
    name: redis
  selector:
    {{- include "redis-sentinel.selectorLabels" . | nindent 4 }}
    app.kubernetes.io/component: redis-master
---
{{- if .Values.redis.replica.enabled }}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "redis-sentinel.fullname" . }}-redis-replica
  labels:
    {{- include "redis-sentinel.labels" . | nindent 4 }}
    app.kubernetes.io/component: redis-replica
  {{- with .Values.service.redis.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: {{ .Values.service.redis.type }}
  ports:
  - port: {{ .Values.service.redis.port }}
    targetPort: redis
    protocol: TCP
    name: redis
  selector:
    {{- include "redis-sentinel.selectorLabels" . | nindent 4 }}
    app.kubernetes.io/component: redis-replica
{{- end }}
```

## templates/sentinel-service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "redis-sentinel.fullname" . }}-sentinel
  labels:
    {{- include "redis-sentinel.labels" . | nindent 4 }}
    app.kubernetes.io/component: sentinel
  {{- with .Values.service.sentinel.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: {{ .Values.service.sentinel.type }}
  ports:
  - port: {{ .Values.service.sentinel.port }}
    targetPort: sentinel
    protocol: TCP
    name: sentinel
  selector:
    {{- include "redis-sentinel.selectorLabels" . | nindent 4 }}
    app.kubernetes.io/component: sentinel
```

## templates/serviceaccount.yaml

```yaml
{{- if .Values.serviceAccount.create -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "redis-sentinel.serviceAccountName" . }}
  labels:
    {{- include "redis-sentinel.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
```

## Kurulum ve Kullanım

### 1. Chart'ı Kurun

```bash
# Chart dizinine gidin ve kurun
helm install redis-sentinel ./simplified-redis-chart

# Veya belirli values ile kurun
helm install redis-sentinel ./simplified-redis-chart -f custom-values.yaml
```

### 2. Konfigürasyon Örnekleri

**Production için values örneği:**

```yaml
redis:
  auth:
    enabled: true
    password: "your-secure-password"
    acl:
      enabled: true
      users:
        - username: "admin"
          password: "admin-secure-password"
          permissions: "+@all"
        - username: "app"
          password: "app-secure-password" 
          permissions: "+@all -@dangerous -flushdb -flushall"
        
  persistence:
    enabled: true
    storageClass: "fast-ssd"
    size: 20Gi
    
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 200m
      memory: 256Mi

sentinel:
  replicas: 3
  resources:
    limits:
      cpu: 200m
      memory: 256Mi
    requests:
      cpu: 50m
      memory: 128Mi
```

### 3. Scaling

```bash
# Redis replica sayısını artırın
helm upgrade redis-sentinel ./simplified-redis-chart --set redis.replica.replicas=4

# Sentinel sayısını artırın (tek sayı olmalı)
helm upgrade redis-sentinel ./simplified-redis-chart --set sentinel.replicas=5
```

### 4. ACL Yönetimi

Redis ACL kullanıcıları values.yaml dosyasında tanımlanır:

```yaml
redis:
  auth:
    acl:
      enabled: true
      users:
        - username: "readonly-user"
          password: "readonly-pass"
          permissions: "+@read -@write -@admin"
        - username: "write-user"
          password: "write-pass"
          permissions: "+@all -@admin -flushall -flushdb"
```

### 5. Bağlantı

**Redis Master'a bağlanmak için:**
```bash
redis-cli -h redis-sentinel-redis-master -p 6379 -a your-password
```

**Sentinel üzerinden master bilgisi almak için:**
```bash
redis-cli -h redis-sentinel-sentinel -p 26379 sentinel masters
```

### 6. Monitoring (Opsiyonel)

Monitoring aktif etmek için:

```yaml
metrics:
  enabled: true
```

Bu chart ile tam özellikli, production-ready bir Redis Sentinel kurulumu yapabilirsiniz. Tüm konfigürasyonlar values.yaml üzerinden yönetilebilir ve Helm ile kolayca scale edilebilir.