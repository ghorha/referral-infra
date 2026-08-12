# ============================================================================
# Outputs for AWS Infrastructure
# ============================================================================

# VPC Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

# EKS Outputs
output "eks_cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "eks_cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.eks.cluster_security_group_id
}

# RDS Outputs
output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = module.rds.port
}

output "rds_database_name" {
  description = "RDS database name"
  value       = module.rds.database_name
}

output "rds_instance_id" {
  description = "RDS instance identifier"
  value       = module.rds.instance_id
}

# Redis Outputs
output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = module.redis.endpoint
}

output "redis_port" {
  description = "ElastiCache Redis port"
  value       = module.redis.port
}

# S3 Outputs
output "s3_files_bucket_name" {
  description = "S3 bucket name for file uploads"
  value       = module.s3.bucket_names["files"]
}

output "s3_data_lake_bucket_name" {
  description = "S3 bucket name for data lake"
  value       = module.s3.bucket_names["data_lake"]
}

# SQS Outputs
output "sqs_analytics_queue_url" {
  description = "SQS analytics queue URL"
  value       = module.sqs.queue_urls["analytics_events"]
}

output "sqs_audit_queue_url" {
  description = "SQS audit queue URL"
  value       = module.sqs.queue_urls["audit_events"]
}

# Secrets Outputs
output "database_secret_arn" {
  description = "ARN of database secret in Secrets Manager"
  value       = aws_secretsmanager_secret.database.arn
}

output "jwt_secret_arn" {
  description = "ARN of JWT secret in Secrets Manager"
  value       = aws_secretsmanager_secret.jwt.arn
}

output "stripe_secret_arn" {
  description = "ARN of Stripe secret in Secrets Manager"
  value       = aws_secretsmanager_secret.stripe.arn
}

# ALB Outputs
output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.dns_name
}

output "alb_zone_id" {
  description = "ALB Route53 zone ID"
  value       = module.alb.zone_id
}

# CloudFront Outputs
output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = module.cloudfront.distribution_id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = module.cloudfront.domain_name
}

# Commands to configure kubectl
output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_id} --region ${var.aws_region}"
}

# Summary
output "deployment_summary" {
  description = "Deployment summary"
  value = {
    environment      = var.environment
    region          = var.aws_region
    eks_cluster     = module.eks.cluster_id
    database_endpoint = module.rds.endpoint
    redis_endpoint  = module.redis.endpoint
    s3_files_bucket = module.s3.bucket_names["files"]
    alb_dns         = module.alb.dns_name
  }
}

