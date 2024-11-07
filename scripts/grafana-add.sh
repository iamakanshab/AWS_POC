#!/bin/bash
# add-grafana.sh

# Add Grafana repo
echo "Adding Grafana repo..."
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create minimal Grafana values
cat << 'EOF' > grafana-minimal.yaml
persistence:
  enabled: false

resources:
  requests:
    cpu: 10m
    memory: 32Mi
  limits:
    cpu: 100m
    memory: 128Mi

# Add Prometheus datasource
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server.monitoring.svc.cluster.local
      access: proxy
      isDefault: true

# Add basic dashboard
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

dashboards:
  default:
    kubernetes:
      gnetId: 315
      revision: 3
      datasource: Prometheus
    node-exporter:
      gnetId: 1860
      revision: 29
      datasource: Prometheus

tolerations:
  - operator: "Exists"

securityContext:
  runAsUser: 472
  runAsGroup: 472
EOF

# Install Grafana
echo "Installing Grafana..."
helm install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-minimal.yaml \
  --debug

# Wait for pods
echo "Waiting for Grafana pod to be ready..."
kubectl wait --for=condition=Ready pods -l "app.kubernetes.io/name=grafana" -n monitoring --timeout=300s

# Create updated port-forward script
cat << 'EOF' > monitoring-portforward.sh
#!/bin/bash
# Kill existing port-forwards
pkill -f "kubectl port-forward.*monitoring" || true
sleep 2

# Start port forwarding
echo "Starting port forwarding..."
kubectl port-forward -n monitoring svc/prometheus-server 9090:80 &
kubectl port-forward -n monitoring svc/grafana 3000:80 &

echo "Access URLs:"
echo "Prometheus: http://localhost:9090"
echo "Grafana: http://localhost:3000"

# Get Grafana admin password
echo -e "\nGrafana admin credentials:"
echo "Username: admin"
echo "Password: $(kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode)"

echo -e "\nPod Status:"
kubectl get pods -n monitoring
EOF

chmod +x monitoring-portforward.sh

# Show status
echo -e "\nChecking pod status..."
kubectl get pods -n monitoring

# Get Grafana password
echo -e "\nGrafana admin credentials:"
echo "Username: admin"
echo "Password: $(kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode)"

echo -e "\nTo start port forwarding, run: ./monitoring-portforward.sh"
