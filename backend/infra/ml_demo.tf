# ML demo service — ephemeral ECS Fargate stack for the LIT-60 handoff window.
# All resources are additive; no edits to backend resources required to deploy or tear down.

resource "aws_cloudwatch_log_group" "ml_demo" {
  name              = "/ecs/${local.name_prefix}-ml-demo"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "ml_demo" {
  family                   = "${local.name_prefix}-ml-demo"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "ml-demo"
      image     = var.ml_demo_image
      essential = true
      portMappings = [
        {
          containerPort = 8001
          hostPort      = 8001
          protocol      = "tcp"
        },
      ]
      environment = [
        {
          name  = "ML_DEMO_ONNX_PATH"
          value = "/app/AI/checkpoints_final/wesad_w2.0/wesad_mamba_v1.onnx"
        },
        {
          name  = "ML_DEMO_MAX_UPLOAD_BYTES"
          value = "5242880"
        },
        {
          name  = "PYTHONPATH"
          value = "/app"
        },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ml_demo.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ml-demo"
        }
      }
    },
  ])

  tags = local.common_tags
}

resource "aws_lb_target_group" "ml_demo" {
  name        = "${local.name_prefix}-ml-demo"
  port        = 8001
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = local.common_tags
}

resource "aws_lb_listener_rule" "ml_demo" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ml_demo.arn
  }

  condition {
    path_pattern {
      values = ["/api/v1/ml-demo/*"]
    }
  }

  tags = local.common_tags
}

resource "aws_ecs_service" "ml_demo" {
  name             = "${local.name_prefix}-ml-demo"
  cluster          = aws_ecs_cluster.main.id
  task_definition  = aws_ecs_task_definition.ml_demo.arn
  desired_count    = 1
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  # Single-task service: allow zero healthy during rollout so we don't need a 2nd task slot.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  # Python + ML deps cold-start is ~10-15s; TG min-healthy time is 60s. 120s grace gives headroom.
  health_check_grace_period_seconds = 120

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ml_demo.arn
    container_name   = "ml-demo"
    container_port   = 8001
  }

  depends_on = [aws_lb_listener_rule.ml_demo]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "ml_demo_unhealthy" {
  alarm_name          = "${local.name_prefix}-ml-demo-unhealthy"
  alarm_description   = "ML demo target group has zero healthy hosts for two consecutive 5-minute periods."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.ml_demo.arn_suffix
    LoadBalancer = aws_lb.api.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}
