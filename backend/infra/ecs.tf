resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.name_prefix}-backend"
  retention_in_days = 14
}

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${local.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name               = "${local.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

data "aws_iam_policy_document" "ecs_task_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_db_instance.postgres.master_user_secret[0].secret_arn,
      aws_secretsmanager_secret.supabase.arn,
      aws_secretsmanager_secret.firebase.arn,
      aws_secretsmanager_secret.sentry.arn,
    ]
  }
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name   = "${local.name_prefix}-execution-secrets"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.ecs_task_secrets.json
}

resource "aws_iam_role_policy" "ecs_task_secrets" {
  name   = "${local.name_prefix}-task-secrets"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_secrets.json
}

data "aws_iam_policy_document" "ecs_task_xray" {
  statement {
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
      "xray:GetSamplingStatisticSummaries",
      "logs:PutLogEvents",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecs_task_xray" {
  name   = "${local.name_prefix}-task-xray"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_xray.json
}

data "aws_iam_policy_document" "ecs_task_bedrock" {
  # Haiku 4.5 in ap-northeast-2 is only available via inference profiles
  # (the foundation-model ID alone returns ValidationException). Requests
  # use the `global.` profile, which routes to the underlying foundation
  # model in whichever supported region has capacity, so we have to grant
  # InvokeModel on both the profile ARN and the foundation-model ARNs in
  # any region the profile may route to.
  statement {
    actions = ["bedrock:InvokeModel"]
    resources = [
      # The Global Anthropic Claude Haiku 4.5 inference profile (account-scoped).
      "arn:aws:bedrock:${var.aws_region}:*:inference-profile/global.anthropic.claude-haiku-4-5-*",
      # The underlying foundation models the profile may route to (any region).
      "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku-4-5-*",
    ]
  }
}

resource "aws_iam_role_policy" "ecs_task_bedrock" {
  name   = "${local.name_prefix}-task-bedrock"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_bedrock.json
}

resource "aws_cloudwatch_log_group" "otel_collector" {
  name              = "/ecs/${local.name_prefix}-otel-collector"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.name_prefix}-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = var.container_image
      essential = true
      command = [
        "sh",
        "-c",
        "export DATABASE_URL=\"postgresql+asyncpg://${var.db_username}:$${DB_PASSWORD}@${aws_db_instance.postgres.address}:5432/${var.db_name}?ssl=require\" && uvicorn app.main:app --host 0.0.0.0 --port 8000"
      ]
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "APP_VERSION", value = var.app_version },
        { name = "LOG_LEVEL", value = "INFO" },
        { name = "DB_HOST", value = aws_db_instance.postgres.address },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = var.db_name },
        { name = "DB_USERNAME", value = var.db_username },
        { name = "S3_BUCKET_SYNC", value = aws_s3_bucket.sync.id },
        { name = "S3_BUCKET_BIOSIGNALS", value = aws_s3_bucket.biosignals.id },
        { name = "TASK_ID", value = "ecs-${var.environment}" },
        { name = "ENVIRONMENT", value = var.environment },
        { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://localhost:4317" },
        { name = "AI_FEATURES_ENABLED", value = var.ai_features_enabled ? "true" : "false" },
      ]
      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_db_instance.postgres.master_user_secret[0].secret_arn}:password::"
        },
        {
          name      = "SUPABASE_URL"
          valueFrom = "${aws_secretsmanager_secret.supabase.arn}:url::"
        },
        {
          name      = "SUPABASE_ANON_KEY"
          valueFrom = "${aws_secretsmanager_secret.supabase.arn}:anon_key::"
        },
        {
          name      = "SUPABASE_SERVICE_ROLE_KEY"
          valueFrom = "${aws_secretsmanager_secret.supabase.arn}:service_role_key::"
        },
        {
          name      = "SUPABASE_JWT_SECRET"
          valueFrom = "${aws_secretsmanager_secret.supabase.arn}:jwt_secret::"
        },
        {
          name      = "GOOGLE_OAUTH_CLIENT_ID"
          valueFrom = "${aws_secretsmanager_secret.supabase.arn}:google_oauth_client_id::"
        },
        {
          name      = "FIREBASE_CREDENTIALS_JSON"
          valueFrom = aws_secretsmanager_secret.firebase.arn
        },
        {
          name      = "SENTRY_DSN"
          valueFrom = aws_secretsmanager_secret.sentry.arn
        },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.backend.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "backend"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
    },
    {
      name      = "otel-collector"
      image     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
      essential = false
      command   = ["--config=/etc/ecs/ecs-default-config.yaml"]
      portMappings = [
        {
          containerPort = 4317
          hostPort      = 4317
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.otel_collector.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "otel"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "backend" {
  name            = "${local.name_prefix}-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.https]
}
