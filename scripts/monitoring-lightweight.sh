#!/bin/bash
# monitoring-lightweight.sh

# Cleanup
echo "Cleaning up previous deployment..."
kubectl delete namespace monitoring
sleep 5
kubectl create namespace monitoring

# Add repositories
echo "Setting up Helm repositories..."
helm repo add prometheus https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Very minimal Prometheus values
cat << 'EOF' > prometheus-light.yaml
server:
  persistentVolume:
    enabled: false
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

alertmanager:
  enabled: false

nodeExporter:
  enabled: true
  resources:
    requests:
      cpu: 25m
      memory: 32Mi

kubeStateMetrics:
  enabled: true
  resources:
    requests:
      cpu: 25m
      memory: 32Mi

pushgateway:
  enabled: false
EOF

# Very minimal Grafana values
cat << 'EOF' > grafana-light.yaml
admin:
  password: admin

persistence:
  enabled: false

resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 100m
    memory: 128Mi

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
EOF

echo "Installing Prometheus..."
helm install prometheus prometheus/prometheus \
  --namespace monitoring \
  --values prometheus-light.yaml \
  --timeout 5m \
  --wait

echo "Installing Grafana..."
helm install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-light.yaml \
  --timeout 5m \
  --wait

# Create port-forward script
cat << 'EOF' > monitoring-portforward.sh
#!/bin/bash

# Function to kill existing port-forwards
kill_port_forwards() {
    echo "Cleaning up existing port-forwards..."
    pkill -f "kubectl port-forward.*monitoring"
}

# Kill existing port-forwards
kill_port_forwards

echo "Starting port forwarding..."
kubectl port-forward -n monitoring svc/grafana 3000:80 &
kubectl port-forward -n monitoring svc/prometheus-server 9090:80 &

echo "Access URLs:"
echo "Grafana: http://localhost:3000 (admin/admin)"
echo "Prometheus: http://localhost:9090"

echo -e "\nPod Status:"
kubectl get pods -n monitoring
EOF

chmod +x monitoring-portforward.sh

# Wait for pods
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n monitoring --timeout=300s || true

# Show final status
echo -e "\nDeployment Status:"
kubectl get pods -n monitoring

echo -e "\nGrafana Credentials:"
echo "URL: http://localhost:3000"
echo "Username: admin"
echo "Password: admin"
echo -e "\nTo start port forwarding, run: ./monitoring-portforward.sh"
