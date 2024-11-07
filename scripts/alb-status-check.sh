#!/bin/bash
# check-alb-status.sh

echo "Checking ALB provisioning status..."

# Function to check ingress status with timeout
check_ingress_status() {
    local start_time=$(date +%s)
    local timeout=600  # 10 minutes timeout
    local check_interval=30  # Check every 30 seconds

    while true; do
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))
        
        if [ $elapsed_time -gt $timeout ]; then
            echo "Timeout waiting for ALB provisioning"
            return 1
        fi

        echo "Time elapsed: ${elapsed_time}s..."
        
        # Check Ingress status
        echo "Checking Ingress status:"
        kubectl get ingress -n monitoring
        
        # Get ALB hostnames
        GRAFANA_URL=$(kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        PROMETHEUS_URL=$(kubectl get ingress prometheus-ingress -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        
        if [ ! -z "$GRAFANA_URL" ] && [ ! -z "$PROMETHEUS_URL" ]; then
            echo -e "\nALB URLs found!"
            echo "Grafana: https://$GRAFANA_URL"
            echo "Prometheus: https://$PROMETHEUS_URL"
            
            # Check if ALBs are responding
            echo -e "\nChecking if ALBs are responding..."
            if curl -k -s -o /dev/null -w "%{http_code}" "https://$GRAFANA_URL" > /dev/null 2>&1; then
                echo "Grafana ALB is responding"
                if curl -k -s -o /dev/null -w "%{http_code}" "https://$PROMETHEUS_URL" > /dev/null 2>&1; then
                    echo "Prometheus ALB is responding"
                    return 0
                fi
            fi
        fi
        
        # Check events for any issues
        echo -e "\nChecking events:"
        kubectl get events -n monitoring --sort-by='.lastTimestamp' | tail -5
        
        # Check ALB controller logs
        echo -e "\nChecking ALB controller logs:"
        kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=5
        
        echo -e "\nWaiting ${check_interval} seconds before next check..."
        sleep $check_interval
    done
}

# Main execution
echo "Starting ALB status check..."
check_ingress_status

if [ $? -eq 0 ]; then
    echo -e "\nALB setup completed successfully!"
    
    # Save URLs to a file
    echo "Grafana: https://$GRAFANA_URL" > monitoring-urls.txt
    echo "Prometheus: https://$PROMETHEUS_URL" >> monitoring-urls.txt
    
    echo "URLs have been saved to monitoring-urls.txt"
else
    echo -e "\nTroubleshooting required. Please check:"
    echo "1. kubectl get events -n monitoring"
    echo "2. kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller"
    echo "3. kubectl describe ingress -n monitoring"
fi
