# ============================================================================
# Variables for AWS Infrastructure
# ============================================================================

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner of the infrastructure"
  type        = string
  default     = "Platform Team"
}

# ============================================================================
# VPC Configuration
# ============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
}

# ============================================================================
# EKS Configuration
# ============================================================================

variable "eks_node_desired_size" {
  description = "Desired number of general nodes"
  type        = number
  default     = 3
}

variable "eks_node_min_size" {
  description = "Minimum number of general nodes"
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximum number of general nodes"
  type        = number
  default     = 10
}

variable "eks_compute_desired_size" {
  description = "Desired number of compute nodes"
  type        = number
  default     = 2
}

variable "eks_compute_min_size" {
  description = "Minimum number of compute nodes"
  type        = number
  default     = 1
}

variable "eks_compute_max_size" {
  description = "Maximum number of compute nodes"
  type        = number
  default     = 5
}

# ============================================================================
# RDS Configuration
# ============================================================================

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.large"
}

variable "rds_allocated_storage" {
  description = "Initial storage allocation in GB"
  type        = number
  default     = 100
}

variable "rds_max_allocated_storage" {
  description = "Maximum storage allocation in GB (autoscaling)"
  type        = number
  default     = 1000
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "referral_user"
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

# ============================================================================
# Redis Configuration
# ============================================================================

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.medium"
}

# ============================================================================
# Application Configuration
# ============================================================================

variable "jwt_secret" {
  description = "JWT secret key (256-bit)"
  type        = string
  sensitive   = true
}

variable "stripe_api_key" {
  description = "Stripe API key"
  type        = string
  sensitive   = true
}

variable "stripe_webhook_secret" {
  description = "Stripe webhook secret"
  type        = string
  sensitive   = true
}

variable "mailgun_api_key" {
  description = "Mailgun API key"
  type        = string
  sensitive   = true
}

variable "mailgun_domain" {
  description = "Mailgun domain"
  type        = string
}

variable "google_vision_credentials" {
  description = "Google Vision API credentials (JSON)"
  type        = string
  sensitive   = true
}

# ============================================================================
# Domain Configuration
# ============================================================================

variable "frontend_domain" {
  description = "Frontend domain name"
  type        = string
  default     = "referralmarketplace.com"
}

variable "frontend_domains" {
  description = "All frontend domains (including subdomains)"
  type        = list(string)
  default     = ["referralmarketplace.com", "www.referralmarketplace.com"]
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for SSL/TLS"
  type        = string
}

variable "admin_ip_whitelist" {
  description = "IP addresses allowed to access admin endpoints"
  type        = list(string)
  default     = []
}

# ============================================================================
# Alerting Configuration
# ============================================================================

variable "alerts_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms"
  type        = string
  default     = ""
}

