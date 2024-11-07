#!/bin/bash
# setup-monitoring-security.sh

# Get ALB DNS names
GRAFANA_ALB=$(kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
PROMETHEUS_ALB=$(kubectl get ingress prometheus-ingress -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Step 1: Setting up SSL certificates..."
# Request certificates
aws acm request-certificate \
    --domain-name $GRAFANA_ALB \
    --validation-method DNS \
    --query 'CertificateArn' \
    --output text > grafana-cert.txt

aws acm request-certificate \
    --domain-name $PROMETHEUS_ALB \
    --validation-method DNS \
    --query 'CertificateArn' \
    --output text > prometheus-cert.txt

echo "Certificate ARNs saved to grafana-cert.txt and prometheus-cert.txt"
echo "Please validate the certificates in ACM console before proceeding"

# Create secure ingress configuration
cat << EOF > secure-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: $(cat grafana-cert.txt)
    alb.ingress.kubernetes.io/ssl-policy: "ELBSecurityPolicy-TLS-1-2-2017-01"
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
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: $(cat prometheus-cert.txt)
    alb.ingress.kubernetes.io/ssl-policy: "ELBSecurityPolicy-TLS-1-2-2017-01"
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

echo "Step 2: Setting up Grafana authentication..."
# Create Grafana admin secret
GRAFANA_PASS=$(openssl rand -base64 32)
kubectl create secret generic grafana-admin \
  --from-literal=admin-password=$GRAFANA_PASS \
  -n monitoring

# Update Grafana config
cat << EOF > grafana-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-config
  namespace: monitoring
data:
  grafana.ini: |
    [security]
    admin_password = ${GRAFANA_PASS}
    disable_initial_admin_creation = false
    [auth]
    disable_login_form = false
    [server]
    root_url = https://${GRAFANA_ALB}
    [alerting]
    enabled = true
EOF

kubectl apply -f grafana-config.yaml

echo "Step 3: Setting up basic Grafana dashboards..."
cat << EOF > grafana-dashboards.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: monitoring
data:
  k8s-cluster-dashboard.json: |
    {
      "title": "Kubernetes Cluster Monitoring",
      "uid": "k8s-cluster-monitoring",
      "panels": [
        {
          "title": "CPU Usage",
          "type": "graph",
          "datasource": "Prometheus",
          "targets": [
            {
              "expr": "sum(rate(container_cpu_usage_seconds_total{container!=\"\"}[5m])) by (pod)"
            }
          ]
        },
        {
          "title": "Memory Usage",
          "type": "graph",
          "datasource": "Prometheus",
          "targets": [
            {
              "expr": "sum(container_memory_usage_bytes{container!=\"\"}) by (pod)"
            }
          ]
        }
      ]
    }
EOF

kubectl apply -f grafana-dashboards.yaml

echo "Step 4: Setting up monitoring alerts..."
cat << EOF > prometheus-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: monitoring-alerts
  namespace: monitoring
spec:
  groups:
  - name: node
    rules:
    - alert: HighCPUUsage
      expr: avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance) < 0.2
      for: 5m
      labels:
        severity: warning
      annotations:
        description: High CPU usage detected
    - alert: HighMemoryUsage
      expr: node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100 < 20
      for: 5m
      labels:
        severity: warning
      annotations:
        description: High memory usage detected
EOF

kubectl apply -f prometheus-alerts.yaml

echo "Step 5: Setting up backup configuration..."
cat << EOF > monitoring-backup.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-backup
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: grafana-backup
  namespace: monitoring
spec:
  schedule: "0 1 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: alpine
            command:
            - /bin/sh
            - -c
            - |
              cp -r /var/lib/grafana/* /backup/
            volumeMounts:
            - name: grafana-storage
              mountPath: /var/lib/grafana
            - name: backup-storage
              mountPath: /backup
          restartPolicy: OnFailure
          volumes:
          - name: grafana-storage
            persistentVolumeClaim:
              claimName: grafana-pvc
          - name: backup-storage
            persistentVolumeClaim:
              claimName: grafana-backup
EOF

kubectl apply -f monitoring-backup.yaml

echo "Setup complete! Important information:"
echo "Grafana Admin Password: $GRAFANA_PASS"
echo "Grafana URL: https://$GRAFANA_ALB"
echo "Prometheus URL: https://$PROMETHEUS_ALB"
echo
echo "Next steps:"
echo "1. Validate SSL certificates in AWS ACM console"
echo "2. Apply the secure ingress configuration after certificates are validated"
echo "3. Set up additional Grafana dashboards as needed"
echo "4. Configure notification channels for alerts"
echo "5. Test the backup system"
