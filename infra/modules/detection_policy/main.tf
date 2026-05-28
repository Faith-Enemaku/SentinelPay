data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition

  name_prefix = lower("${var.project_name}-${var.environment}")

  cloudtrail_name  = "${local.name_prefix}-trail"
  log_bucket_name  = "${local.name_prefix}-cloudtrail-logs-${local.account_id}"
  config_role_name = "${local.name_prefix}-aws-config-role"
  honeytoken_name  = "${local.name_prefix}-honeytoken-user"
  alert_topic_name = "${local.name_prefix}-security-alerts"

  cloudtrail_arn = "arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.cloudtrail_name}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Module      = "detection-policy"
  }
}

# -------------------------------------------------------------------
# SNS alert topic
# -------------------------------------------------------------------

resource "aws_sns_topic" "security_alerts" {
  count = var.enable_honeytoken ? 1 : 0

  name = local.alert_topic_name

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email_alert" {
  count = var.enable_honeytoken && var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.security_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# -------------------------------------------------------------------
# CloudTrail immutable log bucket
# -------------------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket              = local.log_bucket_name
  object_lock_enabled = true

  tags = merge(local.common_tags, {
    Name    = local.log_bucket_name
    Purpose = "immutable-cloudtrail-logs"
  })
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.cloudtrail_log_retention_days
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.cloudtrail_logs
  ]
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    id     = "transition-old-cloudtrail-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  count = var.enable_cloudtrail ? 1 : 0

  statement {
    sid = "DenyInsecureTransport"

    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.cloudtrail_logs[0].arn,
      "${aws_s3_bucket.cloudtrail_logs[0].arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid = "AllowCloudTrailAclCheck"

    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["s3:GetBucketAcl"]

    resources = [
      aws_s3_bucket.cloudtrail_logs[0].arn
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_arn]
    }
  }

  statement {
    sid = "AllowCloudTrailWrite"

    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = [
      "${aws_s3_bucket.cloudtrail_logs[0].arn}/AWSLogs/${local.account_id}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.cloudtrail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail_logs[0].id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy[0].json
}

resource "aws_cloudtrail" "main" {
  count = var.enable_cloudtrail ? 1 : 0

  name                          = local.cloudtrail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs[0].bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [
    aws_s3_bucket_policy.cloudtrail_logs
  ]

  tags = merge(local.common_tags, {
    Name = local.cloudtrail_name
  })
}

# -------------------------------------------------------------------
# GuardDuty
# -------------------------------------------------------------------

resource "aws_guardduty_detector" "main" {
  count = var.enable_guardduty ? 1 : 0

  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-guardduty"
  })
}

# -------------------------------------------------------------------
# Security Hub
# -------------------------------------------------------------------

resource "aws_securityhub_account" "main" {
  count = var.enable_securityhub ? 1 : 0

  enable_default_standards = false
}

resource "aws_securityhub_standards_subscription" "aws_foundational" {
  count = var.enable_securityhub ? 1 : 0

  standards_arn = "arn:${local.partition}:securityhub:${local.region}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [
    aws_securityhub_account.main
  ]
}

# -------------------------------------------------------------------
# AWS Config
# -------------------------------------------------------------------

data "aws_iam_policy_document" "config_assume_role" {
  count = var.enable_config ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "config" {
  count = var.enable_config ? 1 : 0

  name               = local.config_role_name
  assume_role_policy = data.aws_iam_policy_document.config_assume_role[0].json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "config_managed" {
  count = var.enable_config ? 1 : 0

  role       = aws_iam_role.config[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

data "aws_iam_policy_document" "config_delivery" {
  count = var.enable_config && var.enable_cloudtrail ? 1 : 0

  statement {
    sid = "AllowConfigDeliveryToLogBucket"

    effect = "Allow"

    actions = [
      "s3:GetBucketAcl",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.cloudtrail_logs[0].arn
    ]
  }

  statement {
    sid = "AllowConfigWriteToLogBucket"

    effect = "Allow"

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.cloudtrail_logs[0].arn}/config/AWSLogs/${local.account_id}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_iam_role_policy" "config_delivery" {
  count = var.enable_config && var.enable_cloudtrail ? 1 : 0

  name   = "${local.name_prefix}-config-delivery"
  role   = aws_iam_role.config[0].id
  policy = data.aws_iam_policy_document.config_delivery[0].json
}

resource "aws_config_configuration_recorder" "main" {
  count = var.enable_config ? 1 : 0

  name     = "${local.name_prefix}-config-recorder"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.config_managed,
    aws_iam_role_policy.config_delivery
  ]
}

resource "aws_config_delivery_channel" "main" {
  count = var.enable_config && var.enable_cloudtrail ? 1 : 0

  name           = "${local.name_prefix}-config-delivery"
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs[0].bucket
  s3_key_prefix  = "config"

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [
    aws_config_configuration_recorder.main
  ]
}

resource "aws_config_configuration_recorder_status" "main" {
  count = var.enable_config && var.enable_cloudtrail ? 1 : 0

  name       = aws_config_configuration_recorder.main[0].name
  is_enabled = true

  depends_on = [
    aws_config_delivery_channel.main
  ]
}

resource "aws_config_config_rule" "encrypted_volumes" {
  count = var.enable_config ? 1 : 0

  name = "${local.name_prefix}-encrypted-volumes"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [
    aws_config_configuration_recorder_status.main
  ]
}

resource "aws_config_config_rule" "incoming_ssh_disabled" {
  count = var.enable_config ? 1 : 0

  name = "${local.name_prefix}-incoming-ssh-disabled"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  depends_on = [
    aws_config_configuration_recorder_status.main
  ]
}

resource "aws_config_config_rule" "s3_public_read_prohibited" {
  count = var.enable_config ? 1 : 0

  name = "${local.name_prefix}-s3-public-read-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [
    aws_config_configuration_recorder_status.main
  ]
}

resource "aws_config_config_rule" "s3_encryption_enabled" {
  count = var.enable_config ? 1 : 0

  name = "${local.name_prefix}-s3-encryption-enabled"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  }

  depends_on = [
    aws_config_configuration_recorder_status.main
  ]
}

resource "aws_config_config_rule" "cloudtrail_enabled" {
  count = var.enable_config ? 1 : 0

  name = "${local.name_prefix}-cloudtrail-enabled"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_ENABLED"
  }

  depends_on = [
    aws_config_configuration_recorder_status.main
  ]
}

# -------------------------------------------------------------------
# Honeytoken IAM user
# -------------------------------------------------------------------

resource "aws_iam_user" "honeytoken" {
  count = var.enable_honeytoken ? 1 : 0

  name          = local.honeytoken_name
  path          = "/security/honeytokens/"
  force_destroy = true

  tags = merge(local.common_tags, {
    Purpose = "honeytoken-detection"
  })
}

data "aws_iam_policy_document" "honeytoken_deny_all" {
  count = var.enable_honeytoken ? 1 : 0

  statement {
    sid    = "DenyAllActions"
    effect = "Deny"

    actions = ["*"]

    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "honeytoken_deny_all" {
  count = var.enable_honeytoken ? 1 : 0

  name   = "${local.name_prefix}-honeytoken-deny-all"
  user   = aws_iam_user.honeytoken[0].name
  policy = data.aws_iam_policy_document.honeytoken_deny_all[0].json
}

resource "aws_cloudwatch_event_rule" "honeytoken_used" {
  count = var.enable_honeytoken ? 1 : 0

  name        = "${local.name_prefix}-honeytoken-used"
  description = "Detects API activity performed by the monitored honeytoken IAM user."

  event_pattern = jsonencode({
    "detail-type" = ["AWS API Call via CloudTrail"]
    "detail" = {
      "userIdentity" = {
        "type"     = ["IAMUser"]
        "userName" = [aws_iam_user.honeytoken[0].name]
      }
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "honeytoken_to_sns" {
  count = var.enable_honeytoken ? 1 : 0

  rule      = aws_cloudwatch_event_rule.honeytoken_used[0].name
  target_id = "SendHoneytokenAlertToSNS"
  arn       = aws_sns_topic.security_alerts[0].arn
}

data "aws_iam_policy_document" "sns_eventbridge_publish" {
  count = var.enable_honeytoken ? 1 : 0

  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions = ["sns:Publish"]

    resources = [
      aws_sns_topic.security_alerts[0].arn
    ]
  }
}

resource "aws_sns_topic_policy" "security_alerts" {
  count = var.enable_honeytoken ? 1 : 0

  arn    = aws_sns_topic.security_alerts[0].arn
  policy = data.aws_iam_policy_document.sns_eventbridge_publish[0].json
}