#!/bin/bash
# setup-aws-access.sh

# Create IAM policy for ALB ingress controller
cat << 'EOF' > alb-ingress-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVpcs",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "elasticloadbalancing:*",
                "ec2:DescribeInstances",
                "ec2:DescribeTags"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Install AWS Load Balancer Controller
cat << 'EOF' > alb-values.yaml
clusterName: my-sso-cluster
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/AWSLoadBalancerControllerRole
EOF

# Add and update helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install ALB Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --values alb-values.yaml

# Create Ingress for Grafana
cat << 'EOF' > grafana-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
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

# Create Ingress for Prometheus
cat << 'EOF' > prometheus-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-ingress
  namespace: monitoring
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
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

# Apply ingress resources
kubectl apply -f grafana-ingress.yaml
kubectl apply -f prometheus-ingress.yaml

# Update Grafana service to work with ALB
kubectl patch svc grafana -n monitoring -p '{"spec": {"type": "NodePort"}}'
kubectl patch svc prometheus-server -n monitoring -p '{"spec": {"type": "NodePort"}}'

# Wait for ALB to be provisioned
echo "Waiting for ALB to be provisioned..."
sleep 30

# Get ALB URLs
echo "Getting ALB URLs..."
GRAFANA_ALB=$(kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
PROMETHEUS_ALB=$(kubectl get ingress prometheus-ingress -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Access URLs:"
echo "Grafana: https://$GRAFANA_ALB"
echo "Prometheus: https://$PROMETHEUS_ALB"

# Get Grafana credentials
echo -e "\nGrafana Credentials:"
echo "Username: admin"
echo "Password: $(kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode)"
EOF

chmod +x setup-aws-access.sh
