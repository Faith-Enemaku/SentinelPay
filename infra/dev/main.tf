module "network" {
  source = "../modules/network"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
}

module "identity" {
  source = "../modules/identity"

  project_name  = var.project_name
  environment   = var.environment
  github_owner  = var.github_owner
  github_repo   = var.github_repo
  github_branch = var.github_branch
}

module "data" {
  source = "../modules/data"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.network.vpc_id
  vpc_cidr           = var.vpc_cidr
  private_subnet_ids = module.network.private_subnet_ids

  enable_rds         = var.enable_rds
  enable_elasticache = var.enable_elasticache

  db_instance_class = var.db_instance_class
  cache_node_type   = var.cache_node_type
}

module "compute_edge" {
  source = "../modules/compute_edge"

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = module.network.vpc_id
  vpc_cidr           = var.vpc_cidr
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids

  ecs_task_execution_role_arn = module.identity.ecs_task_execution_role_arn
  payments_task_role_arn      = module.identity.payments_task_role_arn
  kyc_task_role_arn           = module.identity.kyc_task_role_arn

  database_secret_arn       = module.data.database_secret_arn
  kyc_documents_bucket_name = module.data.kyc_documents_bucket_name
  kms_key_arn               = module.data.kms_key_arn

  payments_desired_count = var.payments_desired_count
  kyc_desired_count      = var.kyc_desired_count

  waf_rate_limit         = var.waf_rate_limit
  log_retention_days     = var.log_retention_days
  allowed_http_cidrs     = var.allowed_http_cidrs
  cpu_architecture       = var.cpu_architecture
  enable_execute_command = var.enable_execute_command
}

module "detection_policy" {
  source = "../modules/detection_policy"

  project_name = var.project_name
  environment  = var.environment
  alert_email  = var.alert_email

  enable_cloudtrail  = true
  enable_guardduty   = true
  enable_securityhub = true
  enable_config      = true
  enable_honeytoken  = true
}