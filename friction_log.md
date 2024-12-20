# EKS Monitoring Stack Setup Friction Log
Date: November 7, 2024
Author: Akansha Bansal

## Initial Setup Phase

### 1. Prometheus Installation
✅ **What Worked Well**:
- Base Prometheus installation was straightforward
- Node exporter automatically deployed
- Metrics collection started immediately
- Prometheus server and exporters running successfully


❌ **Friction Points**:
- Initial resource constraints caused pending pods
- Had to adjust resource requests and limits
- Storage configuration needed tweaking
- Persistence configuration required additional setup

### 2. Grafana Deployment

✅ **What Worked Well**:
- Basic deployment succeeded
- Prometheus data source integration was automatic
- Default dashboards were included
- Successfully generated secure admin password

❌ **Friction Points**:
- Health check issues initially (connection refused on port 3000)
- Readiness probe failures needed configuration adjustments
- Had to fix pod scheduling issues
- Required multiple iterations of configuration

### 3. AWS Load Balancer Controller

✅ **What Worked Well**:
- Final ALB configuration worked correctly
- Ingress resources created successfully
- Health checks properly configured
- Successfully integrated with existing VPC

❌ **Major Friction Points**:
- Initial installation failed with webhook errors
- Context deadline exceeded errors
- Service account permissions issues
- Multiple attempts needed to get the controller running
- Required cert-manager installation for webhooks
- Webhook service endpoint availability issues

### 4. Security Implementation

✅ **What Worked Well**:
- Basic security group configuration successful
- Network policies implemented correctly
- Grafana authentication setup working
- HTTP to HTTPS redirect configured

❌ **Friction Points**:
- SSL certificate request failed due to long ALB DNS names
- Initial security group updates failed due to permission issues
- Complex ALB security group identification process
- Had to modify approach for SSL certificates


### 5. OIDC Provider Setup
✅ **What Worked Well**:
- Identified existing EKS OIDC provider
- Clear process for adding GitHub OIDC provider
- Successful provider creation

❌ **Friction Points**:
- Initial confusion between EKS and GitHub OIDC providers
- Required specific thumbprint for GitHub provider
- Required understanding of OIDC authentication flow

### 6. IAM Role Configuration
✅ **What Worked Well**:
- Successfully created IAM role
- Proper trust relationship established
- Correct permissions set for EKS access

❌ **Friction Points**:
- Initial role creation failed without proper trust policy
- Complex permission requirements for EKS and ECR
- Needed multiple iterations to get permissions right

### 7. GitHub Actions Setup

### 1. Workflow Configuration
✅ **What Worked Well**:
- Basic workflow structure established
- AWS credentials integration
- Docker build and push steps

❌ **Major Friction Points**:
- Required specific permissions in workflow
- Complex environment variable management
- Needed proper secrets configuration

### 8. Repository Structure
✅ **What Worked Well**:
- Clear directory structure (.github/workflows)
- Kubernetes manifests organization
- Dockerfile placement

❌ **Friction Points**:
- Manual creation of directory structure needed
- Required specific file naming conventions
- Needed proper GitHub secrets setup


## Technical Challenges Encountered

1. **ALB Controller Issues**:
```
Error: INSTALLATION FAILED: context deadline exceeded
```
- Root Cause: Missing proper webhook configuration
- Solution: Installed cert-manager and configured proper certificates

2. **SSL Certificate Issues**:
```
An error occurred (InvalidDomainValidationOptionsException) when calling the RequestCertificate operation: The first domain name can be no longer than 64 characters.
```
- Root Cause: ALB-generated DNS names exceeded ACM limits
- Solution: Modified approach to use ALB's default SSL

3. **Security Group Updates**:
```
An error occurred when trying to identify ALB security groups
```
- Root Cause: Complex ALB naming and permission issues
- Solution: Improved security group lookup logic

4. **OIDC Configuration**:
```json
{
    "OpenIDConnectProviderList": [
        {
            "Arn": "arn:aws:iam::692859939525:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/01D93CF087B8DA3C84FBA80BCAAAD15E"
        }
    ]
}
```
- Root Cause: Only EKS OIDC provider present
- Solution: Added GitHub Actions OIDC provider

5. **Role Trust Relationship**:
```json
"Principal": {
    "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
}
```
- Root Cause: Incorrect federation setup
- Solution: Updated trust policy with correct provider

## Recommendations for Future Deployments

### Infrastructure Preparation
1. Pre-install cert-manager before ALB controller
2. Ensure proper IAM roles and service accounts
3. Configure appropriate resource requests/limits
4. Plan domain names and SSL strategy beforehand
5. Set up OIDC providers first
6. Create roles with proper trust relationships
7. Test permissions before workflow setup
8. Document role ARNs and configurations

### GitHub Configuration
1. Initialize repository structure first
2. Set up secrets before workflow creation
3. Test workflow with minimal deployment
4. Add complexity incrementally

### Security Setup
1. Use custom domain names instead of ALB DNS
2. Implement security groups early in the process
3. Set up network policies before exposing services
4. Prepare SSL certificates in advance

### Configuration Best Practices
1. Start with minimal resource requirements
2. Use explicit health check configurations
3. Configure security groups upfront
4. Implement proper backup strategy early

### Documentation Needs
1. OIDC provider setup steps
2. Role configuration guide
3. Workflow troubleshooting guide
4. Deployment verification steps

## Follow-up Tasks

### Security Enhancements
- [ ] Implement custom domain and SSL certificates
- [ ] Further restrict network policies
- [ ] Implement Pod Security Policies
- [ ] Set up proper backup procedures

### Monitoring Improvements
- [ ] Add custom dashboards
- [ ] Configure alerting rules
- [ ] Set up notification channels
- [ ] Implement logging solution

### Documentation
- [ ] Create runbooks for common issues
- [ ] Document backup and restore procedures
- [ ] Create security incident response plan
- [ ] Document monitoring and alerting procedures

## Success Metrics
1. External accessibility achieved ✅
2. Metrics collection working ✅
3. Basic monitoring operational ✅
4. Load balancer controller functioning ✅
5. Basic security implemented ✅
6. Automated deployment working ✅
7. OIDC authentication successful ✅
8. Role permissions correct ✅
9. Workflow executing properly ✅


## Time Investment
- Initial setup: 1 hour
- Troubleshooting: 2 hours
- Security implementation: 1 hour
- Final configuration: 1 hour
- OIDC Setup: 30 minutes
- Role Configuration: 30 minutes
- Workflow Setup: 1 hour
- Testing and Validation: 1 hour
Total: ~8 hours

## Key Learnings
1. Always start with minimal configurations
2. Test health checks thoroughly
3. Verify IAM permissions first
4. Ensure webhook services are properly configured
5. Plan SSL and domain strategy in advance
6. Consider DNS name length limitations
7. Test security configurations incrementally


## Next Steps

### Security
- [ ] Implement role permission boundaries
- [ ] Add deployment approvals
- [ ] Set up secret rotation
- [ ] Implement security scanning
### CI/CD
- [ ] Add testing steps
- [ ] Implement staging environment
- [ ] Add deployment validation
- [ ] Set up rollback procedures

1. Implement custom domain names
2. Set up proper SSL certificates
3. Configure comprehensive monitoring dashboards
4. Implement proper backup solution
5. Set up alerting and notification system

## Additional Considerations
1. Regular security audits
2. Backup testing procedures
3. Monitoring dashboard templates
4. Incident response procedures
5. Change management process
6. Rollback strategies
7. Environment separation
8. Security best practices
9. Monitoring integration

## Workflow Improvements Needed
1. Add error handling
2. Implement timeout configurations
3. Add deployment validations
4. Include notification systems
5. Add performance monitoring
