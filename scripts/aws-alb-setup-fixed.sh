#!/bin/bash
# setup-alb-access.sh

echo "Creating Ingress resources..."

# Create Ingress for Grafana
cat << 'EOF' > grafana-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 80
EOF

# Create Ingress for Prometheus
cat << 'EOF' > prometheus-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-ingress
  namespace: monitoring
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: prometheus-server
            port:
              number: 80
EOF

# Apply ingress resources
kubectl apply -f grafana-ingress.yaml
kubectl apply -f prometheus-ingress.yaml

# Update services to work with ALB
kubectl patch svc grafana -n monitoring -p '{"spec": {"type": "NodePort"}}' || true
kubectl patch svc prometheus-server -n monitoring -p '{"spec": {"type": "NodePort"}}' || true

# Wait for ALB provisioning
echo "Waiting for ALB to be provisioned (this may take a few minutes)..."
sleep 30

# Function to wait for ALB
wait_for_alb() {
    local retries=0
    local max_retries=20
    while [ $retries -lt $max_retries ]; do
        HOSTNAME=$(kubectl get ingress $1 -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        if [ ! -z "$HOSTNAME" ]; then
            echo $HOSTNAME
            return 0
        fi
        retries=$((retries + 1))
        echo "Waiting for ALB hostname... (attempt $retries/$max_retries)"
        sleep 15
    done
    return 1
}

# Get ALB URLs
echo "Getting ALB URLs..."
GRAFANA_ALB=$(wait_for_alb "grafana-ingress")
PROMETHEUS_ALB=$(wait_for_alb "prometheus-ingress")

if [ ! -z "$GRAFANA_ALB" ] && [ ! -z "$PROMETHEUS_ALB" ]; then
    echo -e "\nAccess URLs:"
    echo "Grafana: https://$GRAFANA_ALB"
    echo "Prometheus: https://$PROMETHEUS_ALB"
    
    echo -e "\nGrafana Credentials:"
    echo "Username: admin"
    GRAFANA_PASSWORD=$(kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
    if [ ! -z "$GRAFANA_PASSWORD" ]; then
        echo "Password: $GRAFANA_PASSWORD"
    else
        echo "Password: admin123 (default)"
    fi
    
    echo -e "\nPlease note:"
    echo "1. It may take a few minutes for the ALB DNS to propagate"
    echo "2. You might see SSL certificate warnings (self-signed certificates)"
    echo "3. To remove these warnings, set up ACM certificates"
else
    echo "Failed to get ALB URLs. Please check:"
    echo "kubectl get ingress -n monitoring"
    echo "kubectl describe ingress -n monitoring"
    echo "kubectl get events -n monitoring"
fi

# Save URLs to a file for reference
echo "Grafana: https://$GRAFANA_ALB" > monitoring-urls.txt
echo "Prometheus: https://$PROMETHEUS_ALB" >> monitoring-urls.txt
