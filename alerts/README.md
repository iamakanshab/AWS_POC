# Setting up Webhooks and Alerts for Slack in Kubernetes

## Overview
This monitoring system provides essential cluster health surveillance through automated Slack alerts. It monitors critical infrastructure components including node health, pod status, and resource utilization (CPU, memory, GPU), triggering immediate notifications when predefined thresholds are breached. The system helps prevent downtime by alerting on critical issues like node failures, pod crashes, and resource exhaustion, while also monitoring quota management and performance metrics. These real-time alerts enable quick response to potential problems, helping maintain optimal cluster performance and reliability.

## Prerequisites
### 1. Check Cluster Status
```bash
# Check cluster nodes
kubectl get nodes

# Check all pods across namespaces
kubectl get pods --all-namespaces
# or shorter version
kubectl get pods -A

# Check cluster health status
kubectl cluster-info

# Check component statuses
kubectl get componentstatuses

# Check running services
kubectl get services --all-namespaces
```

### 2. Verify Required Components
```bash
# Check monitoring namespace
kubectl get namespace monitoring
# Create if missing
kubectl create namespace monitoring

# Check Prometheus Operator
kubectl get pods -n monitoring | grep prometheus-operator
kubectl get crd | grep prometheus
kubectl get prometheusrules --all-namespaces

# Check Flux notification controller
kubectl get deployments -n flux-system
kubectl get pods -n flux-system | grep notification-controller
kubectl get crd | grep notification
```

### 3. Install Missing Components (if needed)
```bash
# Install Prometheus Operator using Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring

# Install Flux
# For macOS
brew install fluxcd/tap/flux
# For Linux
curl -s https://fluxcd.io/install.sh | sudo bash

# Bootstrap Flux
flux install
```

## Setting up Slack Webhook

1. Create Slack App:
   - Visit https://api.slack.com/apps
   - Click "Create New App"
   - Choose "From scratch"
   - Name your app (e.g., "K8s Monitoring")
   - Select your workspace

2. Configure Incoming Webhooks:
   - Go to "Features" → "Incoming Webhooks"
   - Toggle "Activate Incoming Webhooks" to On
   - Click "Add New Webhook to Workspace"
   - Select alert destination channel
   - Click "Allow"

3. Encode Webhook URL:
```bash
# Replace YOUR_WEBHOOK_URL with the URL from Slack
echo -n "YOUR_WEBHOOK_URL" | base64
```

4. Test Webhook:
```bash
curl -X POST -H 'Content-type: application/json' --data '{"text":"Hello from K8s Monitor!"}' YOUR_WEBHOOK_URL
```

## Deploying Alert Configuration

1. Create configuration file (k8s-slack-alerts.yaml):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: slack-webhook
  namespace: monitoring
type: Opaque
data:
  webhook-url: YOUR_BASE64_ENCODED_WEBHOOK_URL

---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: kubernetes-monitoring-alerts
  namespace: monitoring
spec:
  groups:
  - name: kubernetes-system-alerts
    rules:
    - alert: HighCPUUsage
      expr: sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (pod) > 0.8
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High CPU usage on {{ $labels.pod }}"
        description: "Pod {{ $labels.pod }} has high CPU usage (> 80%) for more than 5 minutes"

    - alert: HighMemoryUsage
      expr: sum(container_memory_working_set_bytes{container!=""}) by (pod) / sum(container_spec_memory_limit_bytes{container!=""}) by (pod) > 0.85
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High memory usage on {{ $labels.pod }}"
        description: "Pod {{ $labels.pod }} has high memory usage (> 85%) for more than 5 minutes"

    - alert: PodCrashLooping
      expr: rate(kube_pod_container_status_restarts_total[15m]) * 60 * 5 > 5
      for: 15m
      labels:
        severity: critical
      annotations:
        summary: "Pod {{ $labels.pod }} is crash looping"
        description: "Pod {{ $labels.pod }} has restarted more than 5 times in 15 minutes"

    - alert: NodeNotReady
      expr: kube_node_status_condition{condition="Ready",status="true"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Node {{ $labels.node }} is not ready"
        description: "Node {{ $labels.node }} has been in NotReady state for more than 5 minutes"

---
apiVersion: notification.toolkit.fluxcd.io/v1beta1
kind: Provider
metadata:
  name: slack
  namespace: monitoring
spec:
  type: slack
  channel: alerts
  address: ${SLACK_WEBHOOK_URL}
  secretRef:
    name: slack-webhook

---
apiVersion: notification.toolkit.fluxcd.io/v1beta1
kind: Alert
metadata:
  name: on-call-slack
  namespace: monitoring
spec:
  providerRef:
    name: slack
  eventSeverity: info
  eventSources:
    - kind: PrometheusRule
      name: '*'
  suspend: false
```

2. Apply configuration:
```bash
kubectl apply -f k8s-slack-alerts.yaml
```

3. Verify deployment:
```bash
# Check secret
kubectl get secret slack-webhook -n monitoring

# Check PrometheusRule
kubectl get prometheusrule -n monitoring
```

## Alerts Included
### Critical Priority Alerts
- Node becomes NotReady
- Pod crash looping (>5 restarts/15min)

### Resource Utilization Alerts
- CPU usage >80%
- Memory usage >85%

## Security Notes
- Keep your webhook URL secure and never commit it to version control
- Reset the webhook if it's ever exposed
- Use appropriate RBAC permissions for the monitoring namespace
