#!/bin/bash
# setup-opensource-monitoring.sh

# Create monitoring namespace
kubectl create namespace monitoring

# Add Helm repositories
helm repo add prometheus https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create Prometheus values file
cat << 'EOF' > prometheus-values.yaml
server:
  persistentVolume:
    enabled: true
    size: 50Gi
  retention: 15d
  
  # Basic resource requests
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi

alertmanager:
  enabled: true
  persistentVolume:
    enabled: true
    size: 10Gi

nodeExporter:
  enabled: true

pushgateway:
  enabled: true

# Enable metrics collection from Kubernetes
kubeStateMetrics:
  enabled: true
EOF

# Create Grafana values file
cat << 'EOF' > grafana-values.yaml
admin:
  existingSecret: ""
  userKey: admin
  passwordKey: admin-password
  password: admin  # Change this in production!

persistence:
  enabled: true
  size: 10Gi

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server.monitoring.svc.cluster.local
      access: proxy
      isDefault: true

dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
    - name: 'default'
      orgId: 1
      folder: ''
      type: file
      disableDeletion: false
      editable: true
      options:
        path: /var/lib/grafana/dashboards/default

dashboards:
  default:
    k8s-cluster-monitoring:
      gnetId: 15520  # Kubernetes Cluster Monitoring
      revision: 1
      datasource: Prometheus
    node-exporter:
      gnetId: 1860   # Node Exporter
      revision: 29
      datasource: Prometheus
    pod-monitoring:
      gnetId: 6417   # Kubernetes Pod Monitoring
      revision: 1
      datasource: Prometheus

resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 500m
    memory: 1Gi
EOF

# Install Prometheus
helm install prometheus prometheus/prometheus \
  --namespace monitoring \
  --values prometheus-values.yaml

# Install Grafana
helm install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values.yaml

# Create Service Monitor for Prometheus
cat << 'EOF' > service-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: prometheus-self
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: prometheus
  namespaceSelector:
    matchNames:
      - monitoring
  endpoints:
    - port: http
EOF

kubectl apply -f service-monitor.yaml

# Create port-forwarding script
cat << 'EOF' > monitoring-access.sh
#!/bin/bash

# Port forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-server 9090:80 &

# Port forward Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80 &

# Get Grafana admin password
echo "Grafana admin password: admin"
echo "Grafana URL: http://localhost:3000"
echo "Prometheus URL: http://localhost:9090"

# Get monitoring pod status
echo -e "\nMonitoring Stack Status:"
kubectl get pods -n monitoring
EOF

chmod +x monitoring-access.sh
