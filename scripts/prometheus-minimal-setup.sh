#!/bin/bash
# prometheus-only.sh

# Cleanup
echo "Cleaning up..."
kubectl delete namespace monitoring
sleep 5
kubectl create namespace monitoring

# Add only Prometheus repo
echo "Adding Prometheus repo..."
helm repo remove prometheus || true
helm repo add prometheus https://prometheus-community.github.io/helm-charts
helm repo update

# Create minimal values
cat << 'EOF' > prometheus-bare.yaml
server:
  persistentVolume:
    enabled: false
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
nodeExporter:
  enabled: false
kubeStateMetrics:
  enabled: false
alertmanager:
  enabled: false
pushgateway:
  enabled: false
EOF

# Install only Prometheus server
echo "Installing Prometheus..."
helm install prometheus prometheus/prometheus \
  --namespace monitoring \
  --values prometheus-bare.yaml \
  --timeout 10m \
  --debug \
  --wait

# Show status
echo "Checking pod status..."
kubectl get pods -n monitoring

# Create port-forward script
cat << 'EOF' > prometheus-forward.sh
#!/bin/bash
pkill -f "kubectl port-forward.*monitoring" || true
sleep 2
kubectl port-forward -n monitoring svc/prometheus-server 9090:80 &
echo "Prometheus URL: http://localhost:9090"
EOF

chmod +x prometheus-forward.sh

echo "To start Prometheus port forwarding, run: ./prometheus-forward.sh"
