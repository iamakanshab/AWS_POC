#!/bin/bash
# install-alb-direct.sh

# Get cluster name and AWS account ID
CLUSTER_NAME=$(aws eks describe-cluster --name my-sso-cluster --query "cluster.name" --output text)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
AWS_REGION=$(aws configure get region)

echo "Installing ALB Controller for:"
echo "Cluster: $CLUSTER_NAME"
echo "Account: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"

# Clean up any existing resources
echo "Cleaning up existing resources..."
kubectl delete serviceaccount aws-load-balancer-controller -n kube-system 2>/dev/null || true
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true

# Create IAM policy
echo "Creating IAM policy..."
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy-$CLUSTER_NAME \
    --policy-document file://iam_policy.json || true

# Create IAM role
cat << EOF > trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/oidc.eks.${AWS_REGION}.amazonaws.com/id/$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "oidc.eks.${AWS_REGION}.amazonaws.com/id/$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5):aud": "sts.amazonaws.com",
                    "oidc.eks.${AWS_REGION}.amazonaws.com/id/$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5):sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
                }
            }
        }
    ]
}
EOF

ROLE_NAME="AmazonEKSLoadBalancerControllerRole-$CLUSTER_NAME"
aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document file://trust-policy.json || true

aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy-$CLUSTER_NAME

# Create service account
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}
EOF

# Install cert-manager
echo "Installing cert-manager..."
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.5.4/cert-manager.yaml

# Wait for cert-manager
echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=120s

# Install ALB controller
echo "Installing ALB controller..."
curl -Lo alb-controller.yaml https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/v2.5.4/v2_5_4_full.yaml

# Replace cluster name
sed -i "s/your-cluster-name/$CLUSTER_NAME/g" alb-controller.yaml

# Apply the manifest
kubectl apply -f alb-controller.yaml

# Wait for controller to be ready
echo "Waiting for ALB controller to be ready..."
kubectl wait --for=condition=Available deployment/aws-load-balancer-controller -n kube-system --timeout=120s

# Verify installation
echo "Verifying installation..."
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Show logs
echo "Controller logs:"
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
