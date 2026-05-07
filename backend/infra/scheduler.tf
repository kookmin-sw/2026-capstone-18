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
