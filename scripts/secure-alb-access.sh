#!/bin/bash
# secure-alb.sh

# Get ALB DNS names
GRAFANA_ALB=$(kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
PROMETHEUS_ALB=$(kubectl get ingress prometheus-ingress -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Found ALBs:"
echo "Grafana: $GRAFANA_ALB"
echo "Prometheus: $PROMETHEUS_ALB"

# Get security groups for both ALBs
GRAFANA_SG=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?DNSName=='$GRAFANA_ALB'].SecurityGroups[0]" \
  --output text)

PROMETHEUS_SG=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?DNSName=='$PROMETHEUS_ALB'].SecurityGroups[0]" \
  --output text)

echo "Security Groups:"
echo "Grafana SG: $GRAFANA_SG"
echo "Prometheus SG: $PROMETHEUS_SG"

# Get your current IP
YOUR_IP=$(curl -s ifconfig.me)
echo "Your IP: $YOUR_IP"

# Update security group rules if SG is found
if [ ! -z "$GRAFANA_SG" ]; then
    echo "Updating Grafana security group..."
    aws ec2 update-security-group-rule-descriptions-ingress \
        --group-id $GRAFANA_SG \
        --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=$YOUR_IP/32,Description=HTTP}]"
    
    aws ec2 authorize-security-group-ingress \
        --group-id $GRAFANA_SG \
        --protocol tcp \
        --port 443 \
        --cidr $YOUR_IP/32 \
        --description "HTTPS access"
fi

if [ ! -z "$PROMETHEUS_SG" ]; then
    echo "Updating Prometheus security group..."
    aws ec2 update-security-group-rule-descriptions-ingress \
        --group-id $PROMETHEUS_SG \
        --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=$YOUR_IP/32,Description=HTTP}]"
    
    aws ec2 authorize-security-group-ingress \
        --group-id $PROMETHEUS_SG \
        --protocol tcp \
        --port 443 \
        --cidr $YOUR_IP/32 \
        --description "HTTPS access"
fi

# Show current rules
echo -e "\nCurrent security group rules:"
if [ ! -z "$GRAFANA_SG" ]; then
    echo "Grafana security group rules:"
    aws ec2 describe-security-group-rules \
        --filter "Name=group-id,Values=$GRAFANA_SG" \
        --query 'SecurityGroupRules[?IsEgress==`false`].[FromPort,ToPort,CidrIpv4,Description]' \
        --output table
fi

if [ ! -z "$PROMETHEUS_SG" ]; then
    echo "Prometheus security group rules:"
    aws ec2 describe-security-group-rules \
        --filter "Name=group-id,Values=$PROMETHEUS_SG" \
        --query 'SecurityGroupRules[?IsEgress==`false`].[FromPort,ToPort,CidrIpv4,Description]' \
        --output table
fi

echo -e "\nAccess URLs:"
echo "Grafana: http://$GRAFANA_ALB"
echo "Prometheus: http://$PROMETHEUS_ALB"
