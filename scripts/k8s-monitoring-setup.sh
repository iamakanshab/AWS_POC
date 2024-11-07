#!/bin/bash
# monitoring-setup.sh

# Install Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Add prometheus-community helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack (includes Prometheus, Grafana, and Alertmanager)
cat << 'EOF' > prometheus-values.yaml
grafana:
  adminPassword: "admin"  # Change this!
  persistence:
    enabled: true
    size: 10Gi
  dashboards:
    default:
      kubernetes-cluster:
        gnetId: 15520  # Popular Kubernetes cluster monitoring dashboard
        revision: 1
        datasource: Prometheus
      node-exporter:
        gnetId: 1860   # Node Exporter dashboard
        revision: 29
        datasource: Prometheus

prometheus:
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi

nodeExporter:
  enabled: true

kubeStateMetrics:
  enabled: true
EOF

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values prometheus-values.yaml

# Install metrics server for kubectl top command
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Install k9s for cluster management (optional but very useful)
curl -sS https://webinstall.dev/k9s | bash

# Wait for pods to be ready
echo "Waiting for monitoring stack to be ready..."
kubectl wait --for=condition=Ready pods --all -n monitoring --timeout=300s

# Get Grafana admin password
echo "Grafana admin password: admin"  # Change this in production!

# Get URLs
echo "Access URLs (after port-forward):"
echo "Grafana: http://localhost:3000"
echo "Prometheus: http://localhost:9090"
echo "AlertManager: http://localhost:9093"

# Setup port-forwarding commands in a separate script
cat << 'EOF' > monitoring-portforward.sh
#!/bin/bash
# Port forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &
# Port forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
# Port forward AlertManager
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093 &
EOF

chmod +x monitoring-portforward.sh
