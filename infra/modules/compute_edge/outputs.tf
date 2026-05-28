output "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster."
  value       = aws_ecs_cluster.main.arn
}

output "payments_ecr_repository_url" {
  description = "ECR repository URL for payments-api."
  value       = aws_ecr_repository.payments.repository_url
}

output "kyc_ecr_repository_url" {
  description = "ECR repository URL for kyc-api."
  value       = aws_ecr_repository.kyc.repository_url
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.app.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer."
  value       = aws_lb.app.arn
}

output "alb_security_group_id" {
  description = "Security group ID for the ALB."
  value       = aws_security_group.alb.id
}

output "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS tasks."
  value       = aws_security_group.ecs_tasks.id
}

output "payments_target_group_arn" {
  description = "Target group ARN for payments-api."
  value       = aws_lb_target_group.payments.arn
}

output "kyc_target_group_arn" {
  description = "Target group ARN for kyc-api."
  value       = aws_lb_target_group.kyc.arn
}

output "payments_service_name" {
  description = "ECS service name for payments-api."
  value       = aws_ecs_service.payments.name
}

output "kyc_service_name" {
  description = "ECS service name for kyc-api."
  value       = aws_ecs_service.kyc.name
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL."
  value       = aws_wafv2_web_acl.app.arn
}