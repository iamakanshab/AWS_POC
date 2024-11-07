#!/bin/bash
# complete-alb-setup.sh

echo "Setting up ALB Controller with webhook..."

# Install cert-manager first
echo "Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml

# Wait for cert-manager to be ready
echo "Waiting for cert-manager..."
sleep 30
kubectl wait --for=condition=Ready pods -n cert-manager --all --timeout=120s

# Create webhook configuration
cat << 'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: aws-load-balancer-webhook-certificate
  namespace: kube-system
spec:
  dnsNames:
    - aws-load-balancer-webhook-service.kube-system.svc
    - aws-load-balancer-webhook-service.kube-system.svc.cluster.local
  issuerRef:
    kind: Issuer
    name: aws-load-balancer-selfsigned-issuer
  secretName: aws-load-balancer-webhook-tls
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: aws-load-balancer-selfsigned-issuer
  namespace: kube-system
spec:
  selfSigned: {}
---
apiVersion: v1
kind: Service
metadata:
  name: aws-load-balancer-webhook-service
  namespace: kube-system
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
spec:
  ports:
    - port: 443
      targetPort: 9443
      protocol: TCP
  selector:
    app.kubernetes.io/name: aws-load-balancer-controller
EOF

# Create controller deployment with webhook configuration
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: aws-load-balancer-controller
  template:
    metadata:
      labels:
        app.kubernetes.io/name: aws-load-balancer-controller
    spec:
      serviceAccountName: aws-load-balancer-controller
      containers:
        - name: controller
          image: public.ecr.aws/eks/aws-load-balancer-controller:v2.5.4
          args:
            - --cluster-name=my-sso-cluster
            - --ingress-class=alb
            - --aws-region=us-west-2
            - --webhook-cert-dir=/tmp/k8s-webhook-server/serving-certs
          ports:
            - containerPort: 9443
              name: webhook-server
              protocol: TCP
          volumeMounts:
            - mountPath: /tmp/k8s-webhook-server/serving-certs
              name: cert
              readOnly: true
          resources:
            limits:
              cpu: 200m
              memory: 500Mi
            requests:
              cpu: 100m
              memory: 200Mi
      volumes:
        - name: cert
          secret:
            defaultMode: 420
            secretName: aws-load-balancer-webhook-tls
EOF

# Wait for deployment to be ready
echo "Waiting for controller deployment..."
sleep 30
kubectl wait --for=condition=Ready pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --timeout=120s

# Create ingress class
cat << 'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: alb
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: ingress.k8s.aws/alb
EOF

# Create ingress resources
echo "Creating ingress resources..."
cat << 'EOF' | kubectl apply -f -
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
EOF

echo "Setup complete. Checking status..."
echo "Controller pods:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
echo -e "\nController logs:"
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
echo -e "\nIngress status:"
kubectl get ingress -n monitoring
