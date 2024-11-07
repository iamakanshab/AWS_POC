#!/bin/bash
# fix-monitoring-complete.sh

# Clean up existing resources
helm uninstall prometheus -n monitoring 2>/dev/null || true
helm uninstall grafana -n monitoring 2>/dev/null || true
kubectl delete pvc --all -n monitoring 2>/dev/null || true

# Add Helm repositories
echo "Adding Helm repositories..."
helm repo add prometheus https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

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
  enabled: false

nodeExporter:
  enabled: true

pushgateway:
  enabled: false

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
    kubernetes:
      gnetId: 15520
      revision: 1
      datasource: Prometheus
EOF

# Install prometheus with minimal resources
echo "Installing Prometheus..."
helm install prometheus prometheus/prometheus \
  --namespace monitoring \
  --values prometheus-values-minimal.yaml \
  --wait

# Install grafana with minimal resources
echo "Installing Grafana..."
helm install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values-minimal.yaml \
  --wait

# Create port-forward script
cat << 'EOF' > monitoring-portforward.sh
#!/bin/bash
echo "Starting port forwarding..."
# Port forward Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80 &
# Port forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-server 9090:80 &

echo "Access URLs:"
echo "Grafana: http://localhost:3000 (admin/admin)"
echo "Prometheus: http://localhost:9090"

# Show pod status
echo -e "\nPod Status:"
kubectl get pods -n monitoring
EOF

chmod +x monitoring-portforward.sh

# Show status
echo -e "\nDeployment Status:"
kubectl get pods -n monitoring

echo -e "\nGrafana admin password: admin"
echo "To start port forwarding, run: ./monitoring-portforward.sh"
