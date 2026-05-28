data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  payments_task_role_name = element(split("/", var.payments_task_role_arn), length(split("/", var.payments_task_role_arn)) - 1)
  kyc_task_role_name      = element(split("/", var.kyc_task_role_arn), length(split("/", var.kyc_task_role_arn)) - 1)

  payments_image = "${aws_ecr_repository.payments.repository_url}:${var.payments_image_tag}"
  kyc_image      = "${aws_ecr_repository.kyc.repository_url}:${var.kyc_image_tag}"
}

resource "aws_ecr_repository" "payments" {
  name                 = "${local.name_prefix}/payments-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = var.ecr_force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-payments-ecr"
  })
}

resource "aws_ecr_repository" "kyc" {
  name                 = "${local.name_prefix}/kyc-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = var.ecr_force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kyc-ecr"
  })
}

resource "aws_ecr_lifecycle_policy" "payments" {
  repository = aws_ecr_repository.payments.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "kyc" {
  repository = aws_ecr_repository.kyc.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "payments" {
  name              = "/ecs/${local.name_prefix}/payments-api"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-payments-logs"
  })
}

resource "aws_cloudwatch_log_group" "kyc" {
  name              = "/ecs/${local.name_prefix}/kyc-api"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kyc-logs"
  })
}

resource "aws_iam_role_policy" "payments_data_access" {
  name = "${local.name_prefix}-payments-data-access"
  role = local.payments_task_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadDatabaseSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.database_secret_arn
      },
      {
        Sid    = "DecryptDataKey"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "kyc_data_access" {
  name = "${local.name_prefix}-kyc-data-access"
  role = local.kyc_task_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadDatabaseSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.database_secret_arn
      },
      {
        Sid    = "AccessKycDocumentsBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::${var.kyc_documents_bucket_name}"
      },
      {
        Sid    = "AccessKycDocumentObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.kyc_documents_bucket_name}/*"
      },
      {
        Sid    = "UseDataKmsKey"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Allow public HTTP traffic to the SentinelPay ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from allowed CIDRs"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidrs
  }

  egress {
    description = "Allow outbound traffic to VPC targets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks-sg"
  description = "Allow traffic from ALB to ECS Fargate tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "payments-api traffic from ALB"
    from_port       = var.payments_container_port
    to_port         = var.payments_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "kyc-api traffic from ALB"
    from_port       = var.kyc_container_port
    to_port         = var.kyc_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow outbound traffic for AWS APIs and private services"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-tasks-sg"
  })
}

resource "aws_lb" "app" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = var.public_subnet_ids

  enable_deletion_protection = false
  drop_invalid_header_fields = true
  enable_http2               = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb"
  })
}

resource "aws_lb_target_group" "payments" {
  name        = "${local.name_prefix}-payments-tg"
  port        = var.payments_container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-payments-tg"
  })
}

resource "aws_lb_target_group" "kyc" {
  name        = "${local.name_prefix}-kyc-tg"
  port        = var.kyc_container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kyc-tg"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      message_body = "{\"message\":\"SentinelPay edge is online\"}"
      status_code  = "200"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-http-listener"
  })
}

resource "aws_lb_listener_rule" "payments" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.payments.arn
  }

  condition {
    path_pattern {
      values = var.payments_path_patterns
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-payments-rule"
  })
}

resource "aws_lb_listener_rule" "kyc" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 110

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kyc.arn
  }

  condition {
    path_pattern {
      values = var.kyc_path_patterns
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kyc-rule"
  })
}

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-cluster"
  })
}

resource "aws_ecs_task_definition" "payments" {
  family                   = "${local.name_prefix}-payments-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.payments_task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = "payments-api"
      image     = local.payments_image
      essential = true

      portMappings = [
        {
          containerPort = var.payments_container_port
          hostPort      = var.payments_container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "APP_ENV"
          value = var.environment
        },
        {
          name  = "AWS_REGION"
          value = data.aws_region.current.region
        },
        {
          name  = "PORT"
          value = tostring(var.payments_container_port)
        },
        {
          name  = "DATABASE_SECRET_ARN"
          value = var.database_secret_arn
        },
        {
          name  = "KYC_DOCUMENTS_BUCKET"
          value = var.kyc_documents_bucket_name
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.payments.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "payments-api"
        }
      }

      readonlyRootFilesystem = true

      linuxParameters = {
        initProcessEnabled = true
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-payments-task"
  })
}

resource "aws_ecs_task_definition" "kyc" {
  family                   = "${local.name_prefix}-kyc-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.kyc_task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = "kyc-api"
      image     = local.kyc_image
      essential = true

      portMappings = [
        {
          containerPort = var.kyc_container_port
          hostPort      = var.kyc_container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "APP_ENV"
          value = var.environment
        },
        {
          name  = "AWS_REGION"
          value = data.aws_region.current.region
        },
        {
          name  = "PORT"
          value = tostring(var.kyc_container_port)
        },
        {
          name  = "DATABASE_SECRET_ARN"
          value = var.database_secret_arn
        },
        {
          name  = "KYC_DOCUMENTS_BUCKET"
          value = var.kyc_documents_bucket_name
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.kyc.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "kyc-api"
        }
      }

      readonlyRootFilesystem = true

      linuxParameters = {
        initProcessEnabled = true
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kyc-task"
  })
}

resource "aws_ecs_service" "payments" {
  name            = "${local.name_prefix}-payments-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.payments.arn
  desired_count   = var.payments_desired_count
  launch_type     = "FARGATE"

  platform_version = "LATEST"

  enable_execute_command             = var.enable_execute_command
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  health_check_grace_period_seconds  = 60
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.payments.arn
    container_name   = "payments-api"
    container_port   = var.payments_container_port
  }

  depends_on = [
    aws_lb_listener_rule.payments
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-payments-service"
  })
}

resource "aws_ecs_service" "kyc" {
  name            = "${local.name_prefix}-kyc-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.kyc.arn
  desired_count   = var.kyc_desired_count
  launch_type     = "FARGATE"

  platform_version = "LATEST"

  enable_execute_command             = var.enable_execute_command
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  health_check_grace_period_seconds  = 60
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.kyc.arn
    container_name   = "kyc-api"
    container_port   = var.kyc_container_port
  }

  depends_on = [
    aws_lb_listener_rule.kyc
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kyc-service"
  })
}

resource "aws_wafv2_web_acl" "app" {
  name        = "${local.name_prefix}-web-acl"
  description = "WAF protection for ${local.name_prefix} ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "CustomRateLimit"
    priority = 0

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-sqli-rules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 40

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-web-acl"
  })
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.app.arn
  web_acl_arn  = aws_wafv2_web_acl.app.arn
}