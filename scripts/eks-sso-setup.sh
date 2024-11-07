#!/bin/bash
# eks-sso-setup.sh

# Step 1: Configure AWS SSO credential helper
cat << 'EOF' > ~/.aws/config
[default]
sso_start_url = https://amdaws.awsapps.com/start
sso_region = us-east-1
sso_account_id = YOUR_ACCOUNT_ID
sso_role_name = YOUR_ROLE_NAME
region = us-west-2
output = json
EOF

# Step 2: Login to AWS SSO
aws sso login

# Step 3: Install required tools
# Install kubectl if not present
if ! command -v kubectl &> /dev/null; then
    curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.27.1/2023-04-19/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    mkdir -p $HOME/bin
    mv ./kubectl $HOME/bin/
    export PATH=$HOME/bin:$PATH
fi

# Install eksctl if not present
if ! command -v eksctl &> /dev/null; then
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
fi

# Step 4: Create cluster configuration
cat << 'EOF' > eks-sso-config.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: my-sso-cluster
  region: us-west-2
  version: "1.27"

# IAM configuration for SSO
iam:
  withOIDC: true
  serviceAccounts:
  - metadata:
      name: aws-load-balancer-controller
      namespace: kube-system
    wellKnownPolicies:
      awsLoadBalancerController: true

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
    iam:
      withAddonPolicies:
        albIngress: true
        cloudWatch: true
        autoScaler: true

addons:
  - name: vpc-cni
    version: latest
  - name: coredns
    version: latest
  - name: kube-proxy
    version: latest
EOF

# Step 5: Create the cluster
eksctl create cluster -f eks-sso-config.yaml

# Step 6: Configure kubectl context
aws eks update-kubeconfig --name my-sso-cluster --region us-west-2

# Step 7: Verify cluster
kubectl get nodes
