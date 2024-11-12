#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print section headers
print_section() {
    echo -e "\n${GREEN}=== $1 ===${NC}\n"
}

# Function to print info messages
print_info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

# Function to print errors
print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed"
    exit 1
fi

# Check if aws cli is installed
if ! command -v aws &> /dev/null; then
    print_error "aws cli is not installed"
    exit 1
fi

print_section "Checking Windows Nodes"
WINDOWS_NODES=$(kubectl get nodes -l kubernetes.io/os=windows -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')
INSTANCE_IDS=$(kubectl get nodes -l kubernetes.io/os=windows -o jsonpath='{range .items[*]}{.spec.providerID}{"\n"}{end}' | cut -d '/' -f5)

if [ -z "$WINDOWS_NODES" ]; then
    print_error "No Windows nodes found"
    exit 1
else
    print_info "Found Windows nodes:"
    echo "$WINDOWS_NODES"
fi

print_section "Creating VPC CNI Windows Configuration"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: amazon-vpc-cni-windows-config
  namespace: kube-system
data:
  EKS_CLUSTER: "github-actions-windows-cluster"
  AWS_VPC_K8S_CNI_EXTERNALSNAT: "true"
  AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG: "true"
  WARM_ENI_TARGET: "2"
  WARM_IP_TARGET: "5"
EOF

print_section "Patching VPC CNI DaemonSet"
kubectl patch daemonset aws-node -n kube-system --patch '{"spec": {"template": {"spec": {"containers": [{"name": "aws-node","env": [{"name": "AWS_VPC_K8S_CNI_EXTERNALSNAT","value": "true"}]}]}}}}'

print_section "Checking Node Labels and Taints"
for node in $WINDOWS_NODES; do
    print_info "Checking node $node"
    kubectl describe node $node | grep -A5 "Labels:" | grep "kubernetes.io/os"
    kubectl describe node $node | grep -A5 "Taints:"
done

print_section "Checking ENI Configuration"
for instance in $INSTANCE_IDS; do
    print_info "Checking ENIs for instance $instance"
    aws ec2 describe-network-interfaces --filters "Name=attachment.instance-id,Values=$instance"
done

print_section "Checking VPC CNI Logs"
for node in $WINDOWS_NODES; do
    print_info "Checking aws-node pod logs for node $node"
    POD=$(kubectl get pods -n kube-system -o wide | grep aws-node | grep $node | awk '{print $1}')
    if [ ! -z "$POD" ]; then
        kubectl logs -n kube-system $POD --tail=50
    fi
done

print_section "Checking Windows Pod Status"
kubectl get pods -o wide --all-namespaces | grep -E "$(echo $WINDOWS_NODES | tr ' ' '|')"

print_section "Troubleshooting Summary"
echo "1. Verified Windows nodes: $(echo $WINDOWS_NODES | wc -w) found"
echo "2. Created/Updated VPC CNI Windows configuration"
echo "3. Enabled External SNAT"
echo "4. Checked node labels and taints"
echo "5. Verified ENI configuration"
echo "6. Checked VPC CNI logs"
echo "7. Verified Windows pod status"

print_section "Next Steps"
cat << 'EOF'
If issues persist:
1. Check your deployment YAML for proper Windows tolerations:
   kubectl get deployment <deployment-name> -n <namespace> -o yaml

2. Verify network policies:
   kubectl get networkpolicies --all-namespaces

3. Check Windows node security groups:
   aws ec2 describe-security-groups --group-ids $(aws ec2 describe-instances --instance-ids $INSTANCE_IDS --query 'Reservations[].Instances[].SecurityGroups[].GroupId' --output text)

4. Consider restarting the VPC CNI pods:
   kubectl delete pods -n kube-system -l k8s-app=aws-node
EOF

print_section "Debug Complete"
