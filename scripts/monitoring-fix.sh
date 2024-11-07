#!/bin/bash
# fix-monitoring.sh

# Delete existing resources
helm uninstall prometheus -n monitoring
helm uninstall grafana -n monitoring
kubectl delete pvc --all -n monitoring

# Create new prometheus values with minimal resources
cat << 'EOF' > prometheus-values-minimal.yaml
server:
  persistentVolume:
    enabled: true
    size: 10Gi
    storageClass: gp2
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

alertmanager:
  enabled: false  # Disable to reduce resource usage

nodeExporter:
  enabled: true

pushgateway:
  enabled: false  # Disable to reduce resource usage

kubeStateMetrics:
  enabled: true
EOF

# Create new grafana values with minimal resources
cat << 'EOF' > grafana-values-minimal.yaml
admin:
  password: admin

persistence:
  enabled: true
  size: 5Gi
  storageClass: gp2

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server.monitoring.svc.cluster.local
      access: proxy
      isDefault: true
EOF

# Install prometheus with minimal resources
helm install prometheus prometheus/prometheus \
  --namespace monitoring \
  --values prometheus-values-minimal.yaml

# Install grafana with minimal resources
helm install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values-minimal.yaml

# Wait for pods to be ready
echo "Waiting for pods to start..."
kubectl wait --for=condition=Ready pods --all -n monitoring --timeout=300s

# Show pod status
kubectl get pods -n monitoring
