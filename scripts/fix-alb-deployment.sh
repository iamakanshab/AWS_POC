#!/bin/bash
# fix-alb-deployment.sh

# Get cluster name
CLUSTER_NAME=$(aws eks describe-cluster --name my-sso-cluster --query "cluster.name" --output text)
echo "Cluster Name: $CLUSTER_NAME"

# Create deployment patch
cat << EOF > alb-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
spec:
  template:
    spec:
      containers:
      - name: controller
        args:
        - --cluster-name=$CLUSTER_NAME
        - --ingress-class=alb
        - --aws-vpc-id=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.vpcId" --output text)
        - --aws-region=$(aws configure get region)
EOF

# Patch the deployment
echo "Patching ALB controller deployment..."
kubectl patch deployment aws-load-balancer-controller \
  -n kube-system \
  --patch-file alb-patch.yaml

# Wait for rollout
echo "Waiting for deployment rollout..."
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
kubectl rollout status deployment aws-load-balancer-controller -n kube-system

# Verify the new configuration
echo "Verifying configuration..."
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check logs after patch
echo "Checking logs..."
sleep 10
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Recreate ingress resources if controller is healthy
if [ $? -eq 0 ]; then
    echo "Recreating ingress resources..."
    cat << EOF | kubectl apply -f -
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
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
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
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-ingress
  namespace: monitoring
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /-/healthy
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
spec:
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
fi

echo "Done. Check the status with:"
echo "kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller"
echo "kubectl get ingress -n monitoring"
