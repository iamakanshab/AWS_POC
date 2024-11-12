#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

check_prerequisites() {
    print_section "Checking Prerequisites"
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        print_error "aws cli is not installed"
        exit 1
    fi
    
    # Check if we can access the cluster
    if ! kubectl get nodes &> /dev/null; then
        print_error "Cannot access Kubernetes cluster"
        exit 1
    fi
}

fix_vpc_cni() {
    print_section "Fixing VPC CNI Configuration"
    
    # Create updated VPC CNI ConfigMap
    print_info "Creating VPC CNI ConfigMap for Windows support"
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: amazon-vpc-cni-windows-config
  namespace: kube-system
data:
  AWS_VPC_K8S_CNI_EXTERNALSNAT: "true"
  AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG: "true"
  AWS_VPC_K8S_CNI_EXCLUDE_SNAT_CIDRS: "0.0.0.0/0"
  AWS_VPC_K8S_CNI_VETHPREFIX: "eni"
  AWS_VPC_ENI_MTU: "9001"
  WARM_IP_TARGET: "5"
  MINIMUM_IP_TARGET: "2"
  WARM_ENI_TARGET: "1"
  AWS_VPC_K8S_CNI_LOG_LEVEL: "DEBUG"
EOF
    
    # Update VPC CNI DaemonSet
    print_info "Updating VPC CNI DaemonSet configuration"
    kubectl patch daemonset aws-node -n kube-system --type='json' -p='[
        {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {
                "name": "AWS_VPC_K8S_CNI_EXTERNALSNAT",
                "value": "true"
            }
        },
        {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {
                "name": "AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG",
                "value": "true"
            }
        },
        {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {
                "name": "ENABLE_POD_ENI",
                "value": "true"
            }
        }
    ]'
}

fix_windows_runner_deployment() {
    print_section "Fixing Windows Runner Deployment"
    
    # Update the runner deployment with required configurations
    print_info "Updating runner deployment with network configurations"
    cat <<EOF | kubectl apply -f -
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: windows-runner-deployment
  namespace: actions-runner-system
spec:
  template:
    metadata:
      labels:
        vpc.amazonaws.com/PrivateIPv4Address: "true"
    spec:
      nodeSelector:
        kubernetes.io/os: windows
      tolerations:
      - key: "kubernetes.io/os"
        operator: "Equal"
        value: "windows"
        effect: "NoSchedule"
      containers:
      - name: runner
        image: summerwind/actions-runner-dind
        resources:
          requests:
            cpu: "2"
            memory: "7Gi"
          limits:
            cpu: "2"
            memory: "7Gi"
        env:
        - name: DISABLE_RUNNER_UPDATE
          value: "true"
      securityContext:
        windowsOptions:
          runAsUserName: "ContainerUser"
      volumes:
      - name: work
        emptyDir: {}
EOF
}

restart_vpc_cni() {
    print_section "Restarting VPC CNI Pods"
    
    print_info "Deleting existing VPC CNI pods"
    kubectl delete pods -n kube-system -l k8s-app=aws-node
    
    print_info "Waiting for new pods to be ready"
    kubectl wait --for=condition=ready pods -l k8s-app=aws-node -n kube-system --timeout=120s
}

verify_fixes() {
    print_section "Verifying Fixes"
    
    print_info "Checking VPC CNI pods"
    kubectl get pods -n kube-system -l k8s-app=aws-node -o wide
    
    print_info "Checking Windows nodes"
    kubectl get nodes -l kubernetes.io/os=windows -o wide
    
    print_info "Checking runner pods"
    kubectl get pods -n actions-runner-system -o wide
    
    print_info "Checking VPC CNI logs"
    POD=$(kubectl get pods -n kube-system -l k8s-app=aws-node -o jsonpath='{.items[?(@.spec.nodeSelector.kubernetes\.io/os=="windows")].metadata.name}' | head -n1)
    if [ ! -z "$POD" ]; then
        kubectl logs -n kube-system $POD --tail=50
    fi
}

cleanup_old_resources() {
    print_section "Cleaning Up Old Resources"
    
    print_info "Removing any failed pods"
    kubectl delete pods -n actions-runner-system --field-selector status.phase=Failed
}

main() {
    print_section "Starting EKS Windows Networking Fix"
    
    check_prerequisites
    fix_vpc_cni
    fix_windows_runner_deployment
    restart_vpc_cni
    cleanup_old_resources
    verify_fixes
    
    print_section "Fix Script Complete"
    cat << 'EOF'
Next steps:
1. Verify runner pods are starting correctly:
   kubectl get pods -n actions-runner-system -w

2. Check pod networking:
   kubectl exec -it <pod-name> -n actions-runner-system -- powershell Test-NetConnection github.com -Port 443

3. If issues persist, check:
   - VPC CNI logs: kubectl logs -n kube-system -l k8s-app=aws-node
   - Runner pod logs: kubectl logs -n actions-runner-system <pod-name>
   - Node conditions: kubectl describe node -l kubernetes.io/os=windows

For additional support:
- Review EKS documentation for Windows support
- Check AWS VPC CNI GitHub issues
- Verify IAM roles and security groups
EOF
}

# Run the script
main
