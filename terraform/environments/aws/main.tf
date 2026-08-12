# ============================================================================
# Referral Marketplace - AWS Infrastructure
# ============================================================================
# This Terraform configuration deploys the complete platform to AWS
# Including: EKS, RDS PostgreSQL, ElastiCache Redis, S3, VPC, and more
# ============================================================================

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }

  backend "s3" {
    bucket         = "referral-marketplace-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "ReferralMarketplace"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }
}

# ============================================================================
# VPC Module
# ============================================================================

module "vpc" {
  source = "../../modules/vpc"
  
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  
  enable_nat_gateway   = true
  single_nat_gateway   = var.environment != "production"
  enable_dns_hostnames = true
  
  tags = {
    Name = "referral-marketplace-${var.environment}"
  }
}

# ============================================================================
# EKS Cluster Module
# ============================================================================

module "eks" {
  source = "../../modules/eks"
  
  cluster_name    = "referral-marketplace-${var.environment}"
  cluster_version = "1.28"
  
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  
  node_groups = {
    general = {
      desired_size = var.eks_node_desired_size
      min_size     = var.eks_node_min_size
      max_size     = var.eks_node_max_size
      
      instance_types = ["t3.large"]
      capacity_type  = "ON_DEMAND"
      
      labels = {
        role = "general"
      }
    }
    
    compute = {
      desired_size = var.eks_compute_desired_size
      min_size     = var.eks_compute_min_size
      max_size     = var.eks_compute_max_size
      
      instance_types = ["t3.xlarge"]
      capacity_type  = var.environment == "production" ? "ON_DEMAND" : "SPOT"
      
      labels = {
        role = "compute"
      }
      
      taints = [{
        key    = "compute"
        value  = "true"
        effect = "NoSchedule"
      }]
    }
  }
  
  enable_irsa = true  # IAM Roles for Service Accounts
  
  tags = {
    Environment = var.environment
  }
}

# ============================================================================
# RDS PostgreSQL Module
# ============================================================================

module "rds" {
  source = "../../modules/rds"
  
  identifier = "referral-marketplace-${var.environment}"
  
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = var.rds_instance_class
  
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  storage_encrypted     = true
  
  database_name = "referral_marketplace"
  username      = var.db_username
  password      = var.db_password
  
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.database_subnet_ids
  allowed_security_groups = [module.eks.cluster_security_group_id]
  
  backup_retention_period = var.environment == "production" ? 30 : 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  multi_az               = var.environment == "production"
  deletion_protection    = var.environment == "production"
  skip_final_snapshot    = var.environment != "production"
  
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  
  performance_insights_enabled = true
  
  tags = {
    Environment = var.environment
  }
}

# ============================================================================
# ElastiCache Redis Module
# ============================================================================

module "redis" {
  source = "../../modules/elasticache"
  
  cluster_id = "referral-marketplace-${var.environment}"
  
  engine_version = "7.0"
  node_type      = var.redis_node_type
  num_cache_nodes = var.environment == "production" ? 2 : 1
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  allowed_security_groups = [module.eks.cluster_security_group_id]
  
  automatic_failover_enabled = var.environment == "production"
  multi_az_enabled          = var.environment == "production"
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  
  snapshot_retention_limit = var.environment == "production" ? 5 : 1
  snapshot_window         = "03:00-05:00"
  
  tags = {
    Environment = var.environment
  }
}

# ============================================================================
# S3 Buckets Module
# ============================================================================

module "s3" {
  source = "../../modules/s3"
  
  environment = var.environment
  
  buckets = {
    files = {
      name = "referral-marketplace-files-${var.environment}"
      versioning = var.environment == "production"
      lifecycle_rules = [
        {
          id     = "delete-old-files"
          status = "Enabled"
          expiration_days = 365
        }
      ]
    }
    
    data_lake = {
      name = "referral-marketplace-data-lake-${var.environment}"
      versioning = true
      lifecycle_rules = [
        {
          id     = "transition-to-glacier"
          status = "Enabled"
          transition_days = 90
          storage_class = "GLACIER"
        }
      ]
    }
  }
  
  enable_cors = true
  cors_allowed_origins = var.frontend_domains
  
  tags = {
    Environment = var.environment
  }
}

# ============================================================================
# SQS Queue Module (for Analytics Events)
# ============================================================================

module "sqs" {
  source = "../../modules/sqs"
  
  environment = var.environment
  
  queues = {
    analytics_events = {
      name                      = "referral-marketplace-analytics-${var.environment}"
      message_retention_seconds = 1209600  # 14 days
      visibility_timeout_seconds = 300
      delay_seconds             = 0
      
      enable_dlq = true
      max_receive_count = 3
    }
    
    audit_events = {
      name                      = "referral-marketplace-audit-${var.environment}"
      message_retention_seconds = 1209600
      visibility_timeout_seconds = 300
      
      enable_dlq = true
      max_receive_count = 3
    }
  }
  
  tags = {
    Environment = var.environment
  }
}

# ============================================================================
# Secrets Manager
# ============================================================================

resource "aws_secretsmanager_secret" "database" {
  name = "referral-marketplace/${var.environment}/database"
  
  description = "Database credentials for Referral Marketplace"
  
  tags = {
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id
  
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = module.rds.endpoint
    port     = 5432
    database = "referral_marketplace"
  })
}

resource "aws_secretsmanager_secret" "jwt" {
  name = "referral-marketplace/${var.environment}/jwt"
  
  description = "JWT secret for authentication"
  
  tags = {
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id = aws_secretsmanager_secret.jwt.id
  
  secret_string = jsonencode({
    secret = var.jwt_secret
  })
}

resource "aws_secretsmanager_secret" "stripe" {
  name = "referral-marketplace/${var.environment}/stripe"
  
  description = "Stripe API credentials"
  
  tags = {
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "stripe" {
  secret_id = aws_secretsmanager_secret.stripe.id
  
  secret_string = jsonencode({
    api_key        = var.stripe_api_key
    webhook_secret = var.stripe_webhook_secret
  })
}

# ============================================================================
# IAM Roles for Service Accounts (IRSA)
# ============================================================================

# S3 Access Role for Claim Service
resource "aws_iam_role" "claim_service_s3" {
  name = "referral-marketplace-claim-service-s3-${var.environment}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:sub" = "system:serviceaccount:${var.environment}:claim-service"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "claim_service_s3" {
  role       = aws_iam_role.claim_service_s3.name
  policy_arn = aws_iam_policy.s3_files_access.arn
}

resource "aws_iam_policy" "s3_files_access" {
  name        = "referral-marketplace-s3-files-${var.environment}"
  description = "S3 access for file uploads"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        module.s3.bucket_arns["files"],
        "${module.s3.bucket_arns["files"]}/*"
      ]
    }]
  })
}

# ============================================================================
# CloudFront Distribution (for frontend)
# ============================================================================

module "cloudfront" {
  source = "../../modules/cloudfront"
  
  environment = var.environment
  
  origin_domain_name = var.frontend_domain
  aliases            = var.frontend_domains
  
  certificate_arn = var.acm_certificate_arn
  
  enable_logging = true
  log_bucket    = module.s3.bucket_ids["logs"]
  
  tags = {
    Environment = var.environment
  }
}

# ============================================================================
# Application Load Balancer
# ============================================================================

module "alb" {
  source = "../../modules/alb"
  
  name = "referral-marketplace-${var.environment}"
  
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.public_subnet_ids
  security_groups = [module.vpc.alb_security_group_id]
  
  enable_deletion_protection = var.environment == "production"
  enable_http2              = true
  enable_waf                = var.environment == "production"
  
  certificate_arn = var.acm_certificate_arn
  
  tags = {
    Environment = var.environment
  }
}

# ============================================================================
# WAF (Web Application Firewall) - Production only
# ============================================================================

module "waf" {
  source = "../../modules/waf"
  count  = var.environment == "production" ? 1 : 0
  
  name        = "referral-marketplace-${var.environment}"
  environment = var.environment
  
  rate_limit = 2000  # Requests per 5 minutes
  
  # IP whitelist for admin endpoints
  admin_ip_whitelist = var.admin_ip_whitelist
  
  tags = {
    Environment = var.environment
  }
}

# ============================================================================
# Monitoring & Logging
# ============================================================================

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/referral-marketplace/${var.environment}"
  retention_in_days = var.environment == "production" ? 90 : 7
  
  tags = {
    Environment = var.environment
  }
}

# CloudWatch Alarms
module "cloudwatch_alarms" {
  source = "../../modules/cloudwatch"
  
  environment = var.environment
  
  rds_instance_id = module.rds.instance_id
  elasticache_cluster_id = module.redis.cluster_id
  alb_arn_suffix = module.alb.arn_suffix
  
  sns_topic_arn = var.alerts_sns_topic_arn
  
  tags = {
    Environment = var.environment
  }
}

