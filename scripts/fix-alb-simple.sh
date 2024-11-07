#!/bin/bash
# fix-alb-simple.sh

# Clean up existing deployment
kubectl delete deployment -n kube-system aws-load-balancer-controller

# Create the controller deployment directly
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: aws-load-balancer-controller
  template:
    metadata:
      labels:
        app.kubernetes.io/name: aws-load-balancer-controller
    spec:
      serviceAccountName: aws-load-balancer-controller
      containers:
        - name: controller
          image: public.ecr.aws/eks/aws-load-balancer-controller:v2.5.4
          args:
            - --cluster-name=my-sso-cluster
            - --ingress-class=alb
            - --aws-region=us-west-2
          resources:
            requests:
              cpu: 100m
              memory: 200Mi
EOF

# Wait for pod to be ready
echo "Waiting for controller pod to be ready..."
kubectl wait --for=condition=Ready pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --timeout=120s

# Check status
echo "Checking controller status..."
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Show logs
echo "Controller logs:"
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Recreate ingress
echo "Creating ingress resources..."
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

echo "Done. Check ALB controller status with:"
echo "kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller"
echo "kubectl get ingress -n monitoring"
