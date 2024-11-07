#!/bin/bash
# setup-alb-controller.sh

# Get cluster name
CLUSTER_NAME=$(aws eks describe-cluster --name my-sso-cluster --query "cluster.name" --output text)

# Create IAM policy
cat << 'EOF' > alb-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:CreateServiceLinkedRole",
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeAccountAttributes",
                "ec2:DescribeInternetGateways",
                "elasticloadbalancing:*",
                "ec2:DescribeTargetGroups"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create IAM policy
POLICY_ARN=$(aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://alb-policy.json \
  --query 'Policy.Arn' \
  --output text)

# Create service account
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=$POLICY_ARN \
  --override-existing-serviceaccounts \
  --approve

# Install ALB controller
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install ALB controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Wait for controller to be ready
echo "Waiting for ALB controller to be ready..."
kubectl wait --for=condition=Available deployment/aws-load-balancer-controller -n kube-system --timeout=300s

# Verify installation
echo "ALB Controller status:"
kubectl get deployment -n kube-system aws-load-balancer-controller

# Now recreate the ingress resources
cat << 'EOF' > ingress-minimal.yaml
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
kubectl apply -f ingress-minimal.yaml

echo "Setup completed. Please wait a few minutes for the ALB to be provisioned."
