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
