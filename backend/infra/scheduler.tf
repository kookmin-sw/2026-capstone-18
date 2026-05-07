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
