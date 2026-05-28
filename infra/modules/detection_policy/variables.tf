variable "project_name" {
  description = "Name of the project."
  type        = string
}

variable "environment" {
  description = "Deployment environment such as dev, staging, or prod."
  type        = string
}

variable "alert_email" {
  description = "Email address for security alerts. Leave empty to skip email subscription."
  type        = string
  default     = ""
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail with S3 Object Lock protected log bucket."
  type        = bool
  default     = true
}

variable "enable_guardduty" {
  description = "Enable Amazon GuardDuty threat detection."
  type        = bool
  default     = true
}

variable "enable_securityhub" {
  description = "Enable AWS Security Hub and foundational security standard."
  type        = bool
  default     = true
}

variable "enable_config" {
  description = "Enable AWS Config recorder and baseline managed rules."
  type        = bool
  default     = true
}

variable "enable_honeytoken" {
  description = "Create a monitored decoy IAM user and EventBridge/SNS alert path."
  type        = bool
  default     = true
}

variable "cloudtrail_log_retention_days" {
  description = "Default S3 Object Lock retention period for CloudTrail logs."
  type        = number
  default     = 90
}