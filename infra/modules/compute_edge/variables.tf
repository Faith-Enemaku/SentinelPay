variable "project_name" {
  description = "Project name used for naming resources."
  type        = string
}

variable "environment" {
  description = "Environment name, for example dev."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ECS and ALB resources will be deployed."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the Application Load Balancer."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS Fargate tasks."
  type        = list(string)
}

variable "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role."
  type        = string
}

variable "payments_task_role_arn" {
  description = "ARN of the payments-api ECS task role."
  type        = string
}

variable "kyc_task_role_arn" {
  description = "ARN of the kyc-api ECS task role."
  type        = string
}

variable "database_secret_arn" {
  description = "ARN of the Secrets Manager database credentials secret."
  type        = string
}

variable "kyc_documents_bucket_name" {
  description = "Name of the KYC documents S3 bucket."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used for data encryption."
  type        = string
}

variable "payments_desired_count" {
  description = "Desired number of payments-api ECS tasks."
  type        = number
  default     = 0
}

variable "kyc_desired_count" {
  description = "Desired number of kyc-api ECS tasks."
  type        = number
  default     = 0
}

variable "payments_container_port" {
  description = "Container port for payments-api."
  type        = number
  default     = 8001
}

variable "kyc_container_port" {
  description = "Container port for kyc-api."
  type        = number
  default     = 8002
}

variable "task_cpu" {
  description = "CPU units for each Fargate task."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memory in MiB for each Fargate task."
  type        = number
  default     = 512
}

variable "cpu_architecture" {
  description = "CPU architecture for Fargate tasks."
  type        = string
  default     = "X86_64"
}

variable "payments_image_tag" {
  description = "Image tag for payments-api."
  type        = string
  default     = "latest"
}

variable "kyc_image_tag" {
  description = "Image tag for kyc-api."
  type        = string
  default     = "latest"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 14
}

variable "allowed_http_cidrs" {
  description = "CIDR blocks allowed to reach the public ALB over HTTP."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "waf_rate_limit" {
  description = "Maximum requests per IP in a five-minute period."
  type        = number
  default     = 1000
}

variable "enable_container_insights" {
  description = "Whether to enable ECS Container Insights."
  type        = bool
  default     = false
}

variable "enable_execute_command" {
  description = "Whether to enable ECS Exec for services."
  type        = bool
  default     = false
}

variable "ecr_force_delete" {
  description = "Whether to force-delete ECR repositories even if they contain images."
  type        = bool
  default     = true
}

variable "payments_path_patterns" {
  description = "ALB path patterns routed to payments-api."
  type        = list(string)
  default = [
    "/payments/*",
    "/accounts/*",
    "/transactions/*",
    "/wallets/*",
    "/health"
  ]
}

variable "kyc_path_patterns" {
  description = "ALB path patterns routed to kyc-api."
  type        = list(string)
  default = [
    "/kyc/*",
    "/v1/verify/*",
    "/v1/kyc/*",
    "/documents/*"
  ]
}