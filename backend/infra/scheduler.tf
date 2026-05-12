# ------------------------------------------------------------------------------
# Sprint 7 — EventBridge Scheduler infrastructure
#
# Two scheduled cron jobs (purge_accounts, purge_biosignals) replace the
# in-process _purge_loop. Each schedule targets the same ECS cron task
# definition with a different container command override. Failures land in
# the SQS DLQ defined here; CloudWatch alarms on DLQ depth.
# ------------------------------------------------------------------------------

resource "aws_sqs_queue" "scheduler_dlq" {
  name                      = "${local.name_prefix}-scheduler-dlq"
  message_retention_seconds = 1209600 # 14 days
}

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${local.name_prefix}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "scheduler_ecs_runtask" {
  statement {
    actions   = ["ecs:RunTask"]
    resources = ["${aws_ecs_task_definition.cron.arn_without_revision}:*"]
    condition {
      test     = "ArnLike"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.main.arn]
    }
  }
  statement {
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ecs_task.arn, aws_iam_role.ecs_execution.arn]
  }
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.scheduler_dlq.arn]
  }
}

resource "aws_iam_role_policy" "scheduler_ecs_runtask" {
  name   = "${local.name_prefix}-scheduler-runtask"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_ecs_runtask.json
}

resource "aws_cloudwatch_log_group" "cron" {
  name              = "/ecs/${local.name_prefix}-cron"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "cron" {
  family                   = "${local.name_prefix}-cron"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "cron"
      image     = var.container_image
      essential = true
      # No default command — every schedule sets containerOverrides.command.
      # If a task is launched without an override, it exits 1 immediately,
      # which is the desired loud-failure behavior.
      command = ["sh", "-c", "echo 'cron task launched without command override' && exit 1"]
      environment = [
        { name = "APP_VERSION", value = var.app_version },
        { name = "LOG_LEVEL", value = "INFO" },
        { name = "DB_HOST", value = aws_db_instance.postgres.address },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = var.db_name },
        { name = "DB_USERNAME", value = var.db_username },
        { name = "S3_BUCKET_SYNC", value = aws_s3_bucket.sync.id },
        { name = "S3_BUCKET_BIOSIGNALS", value = aws_s3_bucket.biosignals.id },
        { name = "TASK_ID", value = "ecs-cron-${var.environment}" },
        { name = "ENVIRONMENT", value = var.environment },
        { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://localhost:4317" },
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
          awslogs-group         = aws_cloudwatch_log_group.cron.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "cron"
        }
      }
    }
  ])
}

resource "aws_scheduler_schedule_group" "main" {
  name = "${local.name_prefix}-cron"
}

locals {
  cron_db_url = "postgresql+asyncpg://${var.db_username}:$${DB_PASSWORD}@${aws_db_instance.postgres.address}:5432/${var.db_name}"
}

resource "aws_scheduler_schedule" "purge_accounts" {
  name        = "${local.name_prefix}-purge-accounts"
  group_name  = aws_scheduler_schedule_group.main.name
  description = "Sprint 7: hard-delete users past grace window. Daily 03:00 UTC."

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 3 * * ? *)"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_ecs_cluster.main.arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      # Family-only ARN: EventBridge resolves to the LATEST ACTIVE revision
      # at fire time. CI registers a new cron revision per deploy (with the
      # real image SHA); we want each schedule fire to use the most recent
      # revision rather than whichever one Terraform last wrote.
      task_definition_arn = aws_ecs_task_definition.cron.arn_without_revision
      launch_type         = "FARGATE"
      task_count          = 1

      network_configuration {
        subnets          = aws_subnet.private[*].id
        security_groups  = [aws_security_group.ecs.id]
        assign_public_ip = false
      }
    }

    dead_letter_config {
      arn = aws_sqs_queue.scheduler_dlq.arn
    }

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }

    input = jsonencode({
      containerOverrides = [
        {
          name    = "cron"
          command = ["sh", "-c", "export DATABASE_URL=\"${local.cron_db_url}\" && python -m app.jobs.purge_accounts"]
        }
      ]
    })
  }
}

resource "aws_scheduler_schedule" "purge_biosignals" {
  name        = "${local.name_prefix}-purge-biosignals"
  group_name  = aws_scheduler_schedule_group.main.name
  description = "Sprint 7: wipe biosignal uploads for users with revoked consent. Every 6h."

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(15 */6 * * ? *)"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_ecs_cluster.main.arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      # Family-only ARN: EventBridge resolves to the LATEST ACTIVE revision
      # at fire time. CI registers a new cron revision per deploy (with the
      # real image SHA); we want each schedule fire to use the most recent
      # revision rather than whichever one Terraform last wrote.
      task_definition_arn = aws_ecs_task_definition.cron.arn_without_revision
      launch_type         = "FARGATE"
      task_count          = 1

      network_configuration {
        subnets          = aws_subnet.private[*].id
        security_groups  = [aws_security_group.ecs.id]
        assign_public_ip = false
      }
    }

    dead_letter_config {
      arn = aws_sqs_queue.scheduler_dlq.arn
    }

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }

    input = jsonencode({
      containerOverrides = [
        {
          name    = "cron"
          command = ["sh", "-c", "export DATABASE_URL=\"${local.cron_db_url}\" && python -m app.jobs.purge_biosignals"]
        }
      ]
    })
  }
}

resource "aws_scheduler_schedule" "weekly_reports" {
  name        = "${local.name_prefix}-weekly-reports"
  group_name  = aws_scheduler_schedule_group.main.name
  description = "AI weekly report generation. Sun 02:00 KST = Sat 17:00 UTC."

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 17 ? * SAT *)"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_ecs_cluster.main.arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      # Family-only ARN: EventBridge resolves to the LATEST ACTIVE revision
      # at fire time. CI registers a new cron revision per deploy (with the
      # real image SHA); we want each schedule fire to use the most recent
      # revision rather than whichever one Terraform last wrote.
      task_definition_arn = aws_ecs_task_definition.cron.arn_without_revision
      launch_type         = "FARGATE"
      task_count          = 1

      network_configuration {
        subnets          = aws_subnet.private[*].id
        security_groups  = [aws_security_group.ecs.id]
        assign_public_ip = false
      }
    }

    dead_letter_config {
      arn = aws_sqs_queue.scheduler_dlq.arn
    }

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }

    input = jsonencode({
      containerOverrides = [
        {
          name = "cron"
          command = [
            "sh",
            "-c",
            "export DATABASE_URL=\"${local.cron_db_url}\" && export AI_FEATURES_ENABLED=true && cd /app && PYTHONPATH=/app python scripts/run_weekly_reports.py",
          ]
        }
      ]
    })
  }
}

resource "aws_scheduler_schedule" "send_morning_tips" {
  name        = "${local.name_prefix}-send-morning-tips"
  group_name  = aws_scheduler_schedule_group.main.name
  description = "Daily morning tip push — 07:00 KST = 22:00 UTC. Requires AI_FEATURES_ENABLED=true."

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 22 * * ? *)"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_ecs_cluster.main.arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.cron.arn_without_revision
      launch_type         = "FARGATE"
      task_count          = 1

      network_configuration {
        subnets          = aws_subnet.private[*].id
        security_groups  = [aws_security_group.ecs.id]
        assign_public_ip = false
      }
    }

    dead_letter_config {
      arn = aws_sqs_queue.scheduler_dlq.arn
    }

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }

    input = jsonencode({
      containerOverrides = [
        {
          name = "cron"
          command = [
            "sh",
            "-c",
            "export DATABASE_URL=\"${local.cron_db_url}\" && export AI_FEATURES_ENABLED=true && python -m app.jobs.send_morning_tips",
          ]
        }
      ]
    })
  }
}

resource "aws_scheduler_schedule" "send_sleep_nudges" {
  name        = "${local.name_prefix}-send-sleep-nudges"
  group_name  = aws_scheduler_schedule_group.main.name
  description = "Daily sleep-log nudge for users who didn't log last night — 02:00 UTC."

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 2 * * ? *)"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_ecs_cluster.main.arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.cron.arn_without_revision
      launch_type         = "FARGATE"
      task_count          = 1

      network_configuration {
        subnets          = aws_subnet.private[*].id
        security_groups  = [aws_security_group.ecs.id]
        assign_public_ip = false
      }
    }

    dead_letter_config {
      arn = aws_sqs_queue.scheduler_dlq.arn
    }

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }

    input = jsonencode({
      containerOverrides = [
        {
          name    = "cron"
          command = ["sh", "-c", "export DATABASE_URL=\"${local.cron_db_url}\" && python -m app.jobs.send_sleep_nudges"]
        }
      ]
    })
  }
}
