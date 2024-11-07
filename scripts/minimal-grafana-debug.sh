#!/bin/bash
# debug-grafana.sh

echo "Cleaning up existing resources..."
kubectl delete deployment grafana -n monitoring
kubectl delete service grafana -n monitoring
kubectl delete ingress grafana-ingress -n monitoring
kubectl delete configmap grafana-config -n monitoring

echo "Creating minimal Grafana deployment..."

# Create basic deployment
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:9.5.2
        ports:
        - containerPort: 3000
        readinessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 60
          periodSeconds: 10
        env:
        - name: GF_SERVER_HTTP_PORT
          value: "3000"
        - name: GF_AUTH_ANONYMOUS_ENABLED
          value: "true"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
spec:
  ports:
  - port: 80
    targetPort: 3000
  selector:
    app: grafana
  type: NodePort
EOF

echo "Waiting for Grafana pod to be ready..."
sleep 30

# Check pod status
echo "Pod status:"
kubectl get pods -n monitoring -l app=grafana

# Check pod logs
echo -e "\nPod logs:"
kubectl logs -n monitoring -l app=grafana

# Verify service
echo -e "\nService status:"
kubectl get svc -n monitoring grafana

# Test local access
echo -e "\nTesting local access..."
kubectl port-forward -n monitoring svc/grafana 3000:80 &
sleep 5
curl -I http://localhost:3000/api/health

# Create ingress only if local access works
if [ $? -eq 0 ]; then
  echo -e "\nCreating ingress..."
  cat << 'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/healthcheck-path: /api/health
    alb.ingress.kubernetes.io/healthcheck-port: '3000'
spec:
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
fi

# Verify ALB controller
echo -e "\nChecking ALB controller status:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Print ingress status
echo -e "\nIngress status:"
kubectl get ingress -n monitoring
