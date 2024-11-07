# GitHub Actions and EKS Integration Documentation
Date: November 7, 2024
Version: 1.0

## Executive Summary
This document outlines the integration of GitHub Actions with Amazon EKS for automated deployments. The implementation establishes a secure CI/CD pipeline using OIDC authentication and automated container deployments.

## Table of Contents
1. Introduction
2. Prerequisites
3. Infrastructure Setup
4. Implementation Steps
5. Security Considerations
6. Troubleshooting
7. Best Practices
8. Appendix

## 1. Introduction

### 1.1 Purpose
This documentation describes the setup and configuration of GitHub Actions for automated deployments to Amazon EKS. The integration enables continuous deployment of containerized applications while maintaining security best practices.

### 1.2 Scope
- GitHub Actions workflow configuration
- AWS OIDC authentication setup
- EKS deployment automation
- Security and access management

## 2. Prerequisites

### 2.1 Required Resources
- Amazon EKS cluster
- GitHub repository
- AWS IAM permissions
- Docker registry access (ECR)

### 2.2 Access Requirements
- AWS account with administrator access
- GitHub repository admin privileges
- kubectl access to EKS cluster

## 3. Infrastructure Setup

### 3.1 OIDC Provider Configuration
```bash
# Verify existing providers
aws iam list-open-id-connect-providers

# Add GitHub OIDC provider
aws iam create-open-id-connect-provider \
    --url "https://token.actions.githubusercontent.com" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"
```

### 3.2 IAM Role Setup
Required policies and trust relationships for GitHub Actions:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": "repo:ORG/REPO:*"
                }
            }
        }
    ]
}
```

## 4. Implementation Steps

### 4.1 Repository Structure
```
your-repo/
├── .github/
│   └── workflows/
│       └── deploy.yml
├── k8s/
│   └── deployment.yaml
├── Dockerfile
└── application files
```

### 4.2 Workflow Configuration
```yaml
name: Deploy to EKS
on:
  push: