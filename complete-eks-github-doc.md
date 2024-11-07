# EKS and GitHub Actions Integration: Complete Setup Guide
Document Version: 1.0
Last Updated: November 7, 2024
Author: System Administrator

## Table of Contents
1. Introduction
2. Prerequisites
3. Initial EKS Cluster Setup
4. Monitoring Stack Installation
5. GitHub Actions Integration
6. Troubleshooting
7. Maintenance Procedures
8. Appendices

## 1. Introduction

### 1.1 Purpose
This document provides step-by-step instructions for setting up an EKS cluster with monitoring and GitHub Actions integration.

### 1.2 Scope
- EKS cluster creation and configuration
- Prometheus and Grafana installation
- GitHub Actions CI/CD pipeline setup
- Security and access management

## 2. Prerequisites

### 2.1 Required Tools
- AWS CLI
- kubectl
- eksctl
- Helm
- Git

### 2.2 Access Requirements
- AWS Account with administrator access
- GitHub account with repository access
- Domain name (optional, for SSL)

## 3. Initial EKS Cluster Setup

### 3.1 Install Required Tools
```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
```

### 3.2 Create EKS Cluster
Save as `create-cluster.sh`:
```bash
#!/bin/bash

cat << 'EOF' > cluster-config.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: my-sso-cluster
  region: us-west-2
  version: "1.27"

managedNodeGroups:
  - name: managed-nodes
    instanceType: t3.medium
    minSize: 2
    maxSize: 3
    desiredCapacity: 2
    volumeSize: 50
    ssh:
      allow: false
    labels:
      role: worker
    tags:
      environment: production

addons:
  - name: vpc-cni
    version: latest
  - name: coredns
    version: latest
  - name: kube-proxy
    version: latest
EOF

eksctl create cluster -f cluster-config.yaml
```

## 4. Monitoring Stack Installation

### 4.1 Install Prometheus and Grafana
Save as `install-monitoring.sh`:
```bash
#!/bin/bash

# Add Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring

# Install Prometheus
cat << 'EOF' > prometheus-values.yaml
server:
  persistentVolume:
    enabled: false
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
nodeExporter:
  enabled: true
kubeStateMetrics:
  enabled: true
alertmanager:
  enabled: false
pushgateway:
  enabled: false
EOF

helm install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --values prometheus-values.yaml

# Install Grafana
cat << 'EOF' > grafana-values.yaml
persistence:
  enabled: false
resources:
  requests:
    cpu: 50m
    memory: 128Mi
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server
      access: proxy
      isDefault: true
EOF

helm install grafana grafana/grafana \
  --namespace monitoring \
  --values grafana-values.yaml
```

## 5. GitHub Actions Integration

### 5.1 Set Up OIDC Authentication
Save as `setup-github-oidc.sh`:
```bash
#!/bin/bash

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create OIDC provider
aws iam create-open-id-connect-provider \
    --url "https://token.actions.githubusercontent.com" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"

# Create IAM Role
cat << EOF > trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": "repo:GITHUB_USERNAME/REPO_NAME:*"
                }
            }
        }
    ]
}
EOF

# Create role
aws iam create-role \
    --role-name github-actions-eks-deploy \
    --assume-role-policy-document file://trust-policy.json

# Create policy
cat << EOF > role-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:ListClusters"
            ],
            "Resource": "*"
        }
    ]
}
EOF

aws iam put-role-policy \
    --role-name github-actions-eks-deploy \
    --policy-name eks-access \
    --policy-document file://role-policy.json

# Output Role ARN
ROLE_ARN=$(aws iam get-role --role-name github-actions-eks-deploy --query 'Role.Arn' --output text)
echo "Role ARN: $ROLE_ARN"
```

### 5.2 GitHub Workflow Setup
Create `.github/workflows/deploy.yml`:
```yaml
name: Deploy to EKS
on:
  push:
    branches: [ main ]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - name: Configure AWS Credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
        aws-region: us-west-2
    - name: Deploy to EKS
      run: |
        aws eks update-kubeconfig --name my-sso-cluster
        kubectl apply -f k8s/deployment.yaml
```

## 6. Troubleshooting

### 6.1 Common Issues and Solutions

#### EKS Cluster Issues
```bash
# Check cluster status
eksctl get cluster
# Check node status
kubectl get nodes
```

#### Monitoring Stack Issues
```bash
# Check pods
kubectl get pods -n monitoring
# Check services
kubectl get svc -n monitoring
```

#### GitHub Actions Issues
```bash
# Verify OIDC provider
aws iam list-open-id-connect-providers
# Check role trust relationship
aws iam get-role --role-name github-actions-eks-deploy
```

## 7. Maintenance Procedures

### 7.1 Regular Updates
```bash
# Update EKS
eksctl upgrade cluster --name=my-sso-cluster

# Update Helm charts
helm repo update
helm upgrade prometheus prometheus-community/prometheus -n monitoring
helm upgrade grafana grafana/grafana -n monitoring
```

## 8. Appendices

### 8.1 Useful Commands
```bash
# Get Grafana password
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode

# Port forward services
kubectl port-forward -n monitoring svc/grafana 3000:80
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
```

### 8.2 Security Checklist
- [ ] OIDC provider configured
- [ ] IAM roles properly scoped
- [ ] Network policies in place
- [ ] Monitoring alerts configured
- [ ] Secrets properly managed

Would you like me to:
1. Add more detailed troubleshooting steps?
2. Include additional security configurations?
3. Add specific monitoring dashboards?
4. Expand the maintenance procedures?