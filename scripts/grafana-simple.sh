#!/bin/bash
# setup-grafana-simple.sh

# Create minimal Grafana values
cat << 'EOF' > grafana-simple.yaml
replicas: 1

image:
  repository: grafana/grafana
  tag: latest

persistence:
  enabled: false

initChownData:
  enabled: false

adminPassword: admin123

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server
      access: proxy
      isDefault: true

resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 10m
    memory: 32Mi

tolerations:
- operator: "Exists"
EOF

# Install Grafana
echo "Installing Grafana..."
helm install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-simple.yaml

# Wait for pod
echo "Waiting for Grafana pod to be ready..."
sleep 10

# Show status
echo -e "\nPod Status:"
kubectl get pods -n monitoring

# Create port-forward script
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
echo "Grafana Credentials:"
echo "Username: admin"
echo "Password: admin123"

echo -e "\nPod Status:"
kubectl get pods -n monitoring
EOF

chmod +x monitoring-portforward.sh

echo -e "\nGrafana Credentials:"
echo "Username: admin"
echo "Password: admin123"
echo -e "\nTo start port forwarding, run: ./monitoring-portforward.sh"
