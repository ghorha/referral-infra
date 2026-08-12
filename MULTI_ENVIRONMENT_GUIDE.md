# 🌍 Multi-Environment Deployment Guide

## Overview

**Complete multi-environment setup** with dev, staging, and production configurations that reuse common Terraform modules and Kubernetes resources.

---

## 📊 Environment Configuration

### Three Environments

| Environment | Purpose | Resources | Cost/Month |
|-------------|---------|-----------|------------|
| **Dev** | Development & testing | Minimal | ~$250 |
| **Staging** | Pre-production testing | Medium | ~$600 |
| **Production** | Live platform | Full | ~$1,300 |

---

## 🗂️ File Structure

### Terraform (Reusable Modules)

```
infrastructure/terraform/
├── environments/aws/
│   ├── main.tf              # ✅ SHARED - Same for all environments
│   ├── variables.tf         # ✅ SHARED - Same for all environments
│   ├── outputs.tf           # ✅ SHARED - Same for all environments
│   │
│   ├── dev.tfvars           # ✨ DEV SPECIFIC
│   ├── staging.tfvars       # ✨ STAGING SPECIFIC
│   └── production.tfvars    # ✨ PRODUCTION SPECIFIC
│
└── modules/                 # ✅ SHARED - Reused by all environments
    ├── vpc/
    ├── eks/
    ├── rds/
    ├── elasticache/
    ├── s3/
    └── sqs/
```

**Reusable**: main.tf, variables.tf, outputs.tf, all modules  
**Environment-Specific**: *.tfvars files

### Helm Chart (Reusable Templates)

```
infrastructure/helm/referral-marketplace/
├── Chart.yaml               # ✅ SHARED
├── values.yaml              # ✅ DEFAULT VALUES (base)
├── values-dev.yaml          # ✨ DEV OVERRIDES
├── values-staging.yaml      # ✨ STAGING OVERRIDES
├── values-prod.yaml         # ✨ PRODUCTION VALUES
│
└── templates/               # ✅ SHARED - Reused by all
    ├── deployment.yaml
    ├── service.yaml
    ├── hpa.yaml
    └── ingress.yaml
```

**Reusable**: Chart.yaml, all templates  
**Environment-Specific**: values-*.yaml files

### Kubernetes Manifests (Namespace-Specific)

```
infrastructure/kubernetes/
├── dev/
│   └── secrets.yaml         # ✨ DEV SECRETS
├── staging/
│   └── secrets.yaml         # ✨ STAGING SECRETS
└── production/
    ├── 00-namespace.yaml    # ✨ PRODUCTION CONFIG
    ├── 01-secrets.yaml
    ├── 02-configmap.yaml
    ├── 03-api-gateway.yaml
    └── 04-auth-service.yaml
```

**Environment-Specific**: All Kubernetes manifests (different namespaces)

---

## 🔧 Environment Differences

### Development Environment

**Characteristics:**
- Minimal resources
- Single replicas
- No auto-scaling
- Mock external services
- Single-AZ database
- SPOT instances allowed
- No WAF
- HTTP allowed (no SSL required)
- Latest image tags (auto-deploy)

**Configuration (`dev.tfvars`):**
```hcl
environment = "dev"
vpc_cidr = "10.1.0.0/16"
eks_node_desired_size = 2
rds_instance_class = "db.t3.medium"
redis_node_type = "cache.t3.micro"
```

**Helm Values (`values-dev.yaml`):**
```yaml
global:
  environment: dev
  imagePullPolicy: Always

apiGateway:
  replicaCount: 1
  autoscaling:
    enabled: false
  resources:
    requests:
      cpu: 250m
      memory: 256Mi
```

**Use Case:** Rapid development, feature testing, CI/CD builds

---

### Staging Environment

**Characteristics:**
- Production-like but smaller
- 2 replicas per service
- Auto-scaling enabled
- Real external services (test mode)
- Multi-AZ database (optional)
- ON_DEMAND instances
- Optional WAF
- SSL required
- Versioned image tags

**Configuration (`staging.tfvars`):**
```hcl
environment = "staging"
vpc_cidr = "10.2.0.0/16"
eks_node_desired_size = 2
rds_instance_class = "db.t3.large"
redis_node_type = "cache.t3.small"
```

**Helm Values (`values-staging.yaml`):**
```yaml
global:
  environment: staging
  imagePullPolicy: IfNotPresent

apiGateway:
  replicaCount: 2
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
  resources:
    requests:
      cpu: 250m
      memory: 384Mi
```

**Use Case:** Pre-production testing, QA, integration testing, UAT

---

### Production Environment

**Characteristics:**
- Full resources
- 3+ replicas per service
- Aggressive auto-scaling
- Real external services (live)
- Multi-AZ everything
- ON_DEMAND instances
- WAF enabled
- SSL enforced
- Strict versioning
- Deletion protection
- Long backup retention

**Configuration (`production.tfvars`):**
```hcl
environment = "production"
vpc_cidr = "10.0.0.0/16"
eks_node_desired_size = 3
rds_instance_class = "db.t3.large"
redis_node_type = "cache.t3.medium"
```

**Helm Values (`values.yaml` or `values-prod.yaml`):**
```yaml
global:
  environment: production
  imagePullPolicy: IfNotPresent

apiGateway:
  replicaCount: 3
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 20
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
```

**Use Case:** Live production traffic, real users, real payments

---

## 🚀 Deployment Workflows

### Deploy to Development

```bash
# 1. Create dev infrastructure
cd infrastructure/terraform/environments/aws
terraform workspace select dev || terraform workspace new dev
terraform apply -var-file=dev.tfvars

# 2. Configure kubectl for dev
aws eks update-kubeconfig --name referral-marketplace-dev --region us-east-1

# 3. Create dev namespace
kubectl create namespace dev

# 4. Create secrets (update with Terraform outputs)
kubectl apply -f ../../kubernetes/dev/secrets.yaml

# 5. Deploy application
helm upgrade --install referral-marketplace \
  ../../helm/referral-marketplace \
  --namespace dev \
  -f ../../helm/referral-marketplace/values-dev.yaml \
  --set global.database.host=$(terraform output -raw rds_endpoint | cut -d: -f1) \
  --set global.redis.host=$(terraform output -raw redis_endpoint) \
  --wait

# Total time: ~15 minutes
```

### Deploy to Staging

```bash
# 1. Create staging infrastructure
terraform workspace select staging || terraform workspace new staging
terraform apply -var-file=staging.tfvars

# 2. Configure kubectl for staging
aws eks update-kubeconfig --name referral-marketplace-staging --region us-east-1

# 3. Create staging namespace
kubectl create namespace staging

# 4. Create secrets
kubectl apply -f ../../kubernetes/staging/secrets.yaml

# 5. Deploy application (with specific version)
helm upgrade --install referral-marketplace \
  ../../helm/referral-marketplace \
  --namespace staging \
  -f ../../helm/referral-marketplace/values-staging.yaml \
  --set apiGateway.image.tag=v1.0.0 \
  --set authService.image.tag=v1.0.0 \
  # ... set all service tags to specific version
  --wait

# Total time: ~20 minutes
```

### Deploy to Production

```bash
# 1. Create production infrastructure
terraform workspace select production || terraform workspace new production
terraform apply -var-file=production.tfvars

# 2. Configure kubectl for production
aws eks update-kubeconfig --name referral-marketplace-production --region us-east-1

# 3. Create production namespace
kubectl create namespace production

# 4. Create secrets (from AWS Secrets Manager)
# Use External Secrets Operator or manually create from Secrets Manager

# 5. Deploy application (with tested version from staging)
helm upgrade --install referral-marketplace \
  ../../helm/referral-marketplace \
  --namespace production \
  -f ../../helm/referral-marketplace/values.yaml \
  --set apiGateway.image.tag=v1.0.0 \
  # ... all services same tested version
  --wait --timeout 20m

# Total time: ~25-30 minutes
```

---

## 📋 Environment Comparison

### Infrastructure Resources

| Resource | Dev | Staging | Production |
|----------|-----|---------|------------|
| **VPC CIDR** | 10.1.0.0/16 | 10.2.0.0/16 | 10.0.0.0/16 |
| **EKS Nodes** | 1-4 | 2-6 | 2-10 |
| **Instance Type** | t3.large | t3.large | t3.large |
| **RDS Instance** | db.t3.medium | db.t3.large | db.t3.large |
| **RDS Multi-AZ** | ❌ No | ⚠️ Optional | ✅ Yes |
| **Read Replicas** | ❌ No | ❌ No | ✅ Yes (2) |
| **Redis Type** | cache.t3.micro | cache.t3.small | cache.t3.medium |
| **Redis Multi-AZ** | ❌ No | ⚠️ Optional | ✅ Yes |
| **WAF** | ❌ No | ⚠️ Optional | ✅ Yes |
| **Backup Retention** | 1 day | 7 days | 30 days |
| **Deletion Protection** | ❌ No | ⚠️ Optional | ✅ Yes |

### Application Configuration

| Setting | Dev | Staging | Production |
|---------|-----|---------|------------|
| **Pod Replicas** | 1 | 2 | 3+ |
| **Auto-scaling** | ❌ Disabled | ✅ Enabled | ✅ Enabled |
| **SSL/TLS** | ⚠️ Optional | ✅ Required | ✅ Required |
| **Stripe Mode** | Mock/Test | Test | Live |
| **Mailgun** | Mock | Real (test) | Real (live) |
| **OCR** | Mock | Real | Real |
| **S3 Storage** | Real | Real | Real |
| **Rate Limiting** | ⚠️ Relaxed | ✅ Normal | ✅ Strict |
| **Log Level** | DEBUG | INFO | WARN |
| **Metrics** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Image Pull** | Always | IfNotPresent | IfNotPresent |
| **Image Tag** | latest | version | version |

---

## 🔄 Promotion Workflow

### Dev → Staging → Production

```bash
# 1. Develop feature in dev
# Deploy to dev with 'latest' tag
helm upgrade referral-marketplace ... -f values-dev.yaml

# Test in dev
# Run integration tests
# Verify functionality

# 2. Tag release for staging
git tag -a v1.1.0 -m "Release v1.1.0"
git push origin v1.1.0

# Build and push versioned images
docker tag auth-service:latest auth-service:v1.1.0
docker push ECR/auth-service:v1.1.0
# ... for all services

# 3. Deploy to staging with version
helm upgrade referral-marketplace ... \
  -f values-staging.yaml \
  --set authService.image.tag=v1.1.0 \
  # ... all services

# Test in staging
# Run E2E tests
# Performance testing
# Security testing

# 4. Deploy to production (if staging passes)
helm upgrade referral-marketplace ... \
  -f values.yaml \
  --set authService.image.tag=v1.1.0 \
  # ... all services

# Monitor closely
# Gradual rollout (blue-green)
# Ready to rollback if issues
```

---

## 📝 Environment-Specific Files

### Files to Customize Per Environment

#### Terraform
- ✨ **dev.tfvars** - Dev configuration
- ✨ **staging.tfvars** - Staging configuration
- ✨ **production.tfvars** - Production configuration

#### Helm
- ✨ **values-dev.yaml** - Dev values
- ✨ **values-staging.yaml** - Staging values
- ✨ **values.yaml** - Production values (default)

#### Kubernetes
- ✨ **kubernetes/dev/secrets.yaml** - Dev secrets
- ✨ **kubernetes/staging/secrets.yaml** - Staging secrets
- ✨ **kubernetes/production/01-secrets.yaml** - Production secrets

### Files Shared Across All Environments

#### Terraform
- ✅ **main.tf** - Infrastructure definition
- ✅ **variables.tf** - Variable declarations
- ✅ **outputs.tf** - Output definitions
- ✅ **modules/** - All modules

#### Helm
- ✅ **Chart.yaml** - Chart metadata
- ✅ **templates/** - All templates

---

## 🎯 Quick Deployment Commands

### Dev Environment
```bash
# Terraform
terraform workspace select dev
terraform apply -var-file=dev.tfvars

# Helm
helm upgrade --install referral-marketplace \
  ./helm/referral-marketplace \
  --namespace dev \
  -f ./helm/referral-marketplace/values-dev.yaml

# Access
http://api-dev.referralmarketplace.com
```

### Staging Environment
```bash
# Terraform
terraform workspace select staging
terraform apply -var-file=staging.tfvars

# Helm
helm upgrade --install referral-marketplace \
  ./helm/referral-marketplace \
  --namespace staging \
  -f ./helm/referral-marketplace/values-staging.yaml

# Access
https://api-staging.referralmarketplace.com
```

### Production Environment
```bash
# Terraform
terraform workspace select production
terraform apply -var-file=production.tfvars

# Helm
helm upgrade --install referral-marketplace \
  ./helm/referral-marketplace \
  --namespace production \
  -f ./helm/referral-marketplace/values.yaml

# Access
https://api.referralmarketplace.com
```

---

## 🔐 Secrets Management

### Development
```bash
# Simple Kubernetes secrets (plain text OK for dev)
kubectl create secret generic database-secret \
  --from-literal=password=dev_password \
  -n dev
```

### Staging
```bash
# Mix of Kubernetes secrets and AWS Secrets Manager
kubectl create secret generic database-secret \
  --from-literal=password=$(aws secretsmanager get-secret-value \
    --secret-id staging/database/password \
    --query SecretString --output text) \
  -n staging
```

### Production
```bash
# Use External Secrets Operator + AWS Secrets Manager
# Secrets automatically synced from AWS Secrets Manager

# Install External Secrets Operator
helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace

# Create SecretStore
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: production
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
EOF

# Secrets auto-sync from AWS Secrets Manager
```

---

## 📊 Resource Sizing Comparison

### Pod Resources

| Service | Dev | Staging | Production |
|---------|-----|---------|------------|
| **API Gateway** | 1 pod, 250m CPU | 2 pods, 250m CPU | 3-20 pods, 500m CPU |
| **Auth Service** | 1 pod, 100m CPU | 2 pods, 200m CPU | 2-10 pods, 250m CPU |
| **Claim Service** | 1 pod, 200m CPU | 2 pods, 300m CPU | 2-15 pods, 500m CPU |
| **Other Services** | 1 pod, 100m CPU | 2 pods, 200m CPU | 2-10 pods, 250m CPU |

### Database

| Metric | Dev | Staging | Production |
|--------|-----|---------|------------|
| **Instance** | db.t3.medium | db.t3.large | db.t3.large |
| **Storage** | 20 GB | 50 GB | 100 GB |
| **Multi-AZ** | No | Optional | Yes |
| **Backups** | 1 day | 7 days | 30 days |
| **Replicas** | 0 | 0 | 2 read replicas |

---

## 🔄 Environment Lifecycle

### Creating New Environment

```bash
# 1. Copy tfvars template
cp production.tfvars new-env.tfvars

# 2. Edit values for new environment
vi new-env.tfvars
# Change: environment, vpc_cidr, resource sizes

# 3. Create Terraform workspace
terraform workspace new new-env

# 4. Deploy infrastructure
terraform apply -var-file=new-env.tfvars

# 5. Copy Helm values
cp values-staging.yaml values-new-env.yaml

# 6. Edit Helm values
vi values-new-env.yaml

# 7. Deploy application
helm install referral-marketplace ... \
  -f values-new-env.yaml \
  --namespace new-env
```

### Destroying Environment

```bash
# 1. Delete Kubernetes resources
helm uninstall referral-marketplace -n ENVIRONMENT
kubectl delete namespace ENVIRONMENT

# 2. Destroy Terraform infrastructure
terraform workspace select ENVIRONMENT
terraform destroy -var-file=ENVIRONMENT.tfvars

# WARNING: This deletes all data! Backup first!
```

---

## 📊 Environment Configuration Matrix

### Terraform tfvars Comparison

| Variable | Dev | Staging | Production |
|----------|-----|---------|------------|
| environment | "dev" | "staging" | "production" |
| vpc_cidr | 10.1.0.0/16 | 10.2.0.0/16 | 10.0.0.0/16 |
| eks_node_desired | 2 | 2 | 3 |
| eks_node_max | 4 | 6 | 10 |
| rds_instance_class | db.t3.medium | db.t3.large | db.t3.large |
| rds_storage | 20 GB | 50 GB | 100 GB |
| redis_node_type | cache.t3.micro | cache.t3.small | cache.t3.medium |

### Helm Values Comparison

| Setting | Dev | Staging | Production |
|---------|-----|---------|------------|
| imagePullPolicy | Always | IfNotPresent | IfNotPresent |
| image.tag | latest | v1.x.x | v1.x.x |
| replicaCount | 1 | 2 | 3+ |
| autoscaling | disabled | enabled | enabled |
| resources.cpu | 100-250m | 200-300m | 250-500m |
| resources.memory | 256-512Mi | 384-768Mi | 512Mi-1Gi |
| ssl | optional | required | required |
| monitoring | basic | full | full |

---

## ✅ Multi-Environment Setup Complete

### Files Created

**Terraform (Environment-Specific):**
- ✅ dev.tfvars
- ✅ staging.tfvars
- ✅ production.tfvars (updated from example)

**Helm Values (Environment-Specific):**
- ✅ values-dev.yaml
- ✅ values-staging.yaml
- ✅ values.yaml (production default)

**Kubernetes Secrets:**
- ✅ kubernetes/dev/secrets.yaml
- ✅ kubernetes/staging/secrets.yaml
- ✅ kubernetes/production/01-secrets.yaml (already existed)

**Documentation:**
- ✅ MULTI_ENVIRONMENT_GUIDE.md

**Total New Files**: 8

---

## 🎯 Best Practices Implemented

### Infrastructure as Code
- ✅ Reusable Terraform modules
- ✅ Environment-specific tfvars
- ✅ Terraform workspaces for isolation
- ✅ DRY principle (Don't Repeat Yourself)

### Kubernetes Deployment
- ✅ Reusable Helm templates
- ✅ Environment-specific values
- ✅ Namespace isolation
- ✅ Consistent structure

### Security
- ✅ Different secrets per environment
- ✅ AWS Secrets Manager in production
- ✅ Network isolation per environment
- ✅ Least privilege IAM roles

### Cost Optimization
- ✅ Right-sized resources per environment
- ✅ Dev uses minimal resources
- ✅ Staging mimics production
- ✅ Production has full redundancy

---

## 🎊 MULTI-ENVIRONMENT DEPLOYMENT READY

```
╔════════════════════════════════════════════════════╗
║   MULTI-ENVIRONMENT INFRASTRUCTURE ✅               ║
╠════════════════════════════════════════════════════╣
║                                                    ║
║  ✅ Dev Environment      (~$250/month)             ║
║  ✅ Staging Environment  (~$600/month)             ║
║  ✅ Production Environment (~$1,300/month)         ║
║                                                    ║
║  ✅ Reusable Terraform Modules                     ║
║  ✅ Reusable Helm Templates                        ║
║  ✅ Environment-Specific Configs                   ║
║  ✅ Complete Documentation                         ║
║                                                    ║
║  STATUS: READY TO DEPLOY ALL ENVIRONMENTS 🚀       ║
║                                                    ║
╚════════════════════════════════════════════════════╝
```

**Platform can now be deployed to dev, staging, and production with consistent, reusable configurations!** ✅
