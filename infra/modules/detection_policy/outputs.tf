output "cloudtrail_name" {
  description = "Name of the CloudTrail trail."
  value       = try(aws_cloudtrail.main[0].name, null)
}

output "cloudtrail_log_bucket" {
  description = "S3 bucket used for CloudTrail logs."
  value       = try(aws_s3_bucket.cloudtrail_logs[0].bucket, null)
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID."
  value       = try(aws_guardduty_detector.main[0].id, null)
}

output "securityhub_enabled" {
  description = "Whether Security Hub was enabled by this module."
  value       = var.enable_securityhub
}

output "config_recorder_name" {
  description = "AWS Config recorder name."
  value       = try(aws_config_configuration_recorder.main[0].name, null)
}

output "honeytoken_user_name" {
  description = "Honeytoken IAM user name."
  value       = try(aws_iam_user.honeytoken[0].name, null)
}

output "security_alert_topic_arn" {
  description = "SNS topic ARN for security alerts."
  value       = try(aws_sns_topic.security_alerts[0].arn, null)
}