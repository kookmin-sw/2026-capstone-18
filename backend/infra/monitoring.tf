resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# 1. High HTTP error rate on the ALB target group (>5% for 10 minutes).
resource "aws_cloudwatch_metric_alarm" "alb_high_5xx_rate" {
  alarm_name          = "${local.name_prefix}-alb-5xx-rate"
  alarm_description   = "ALB 5xx error rate above 5% for 10 minutes."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 0.05
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "error_rate"
    expression  = "errors / requests"
    label       = "5xx error rate"
    return_data = true
  }
  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 300
      stat        = "Sum"
      dimensions = {
        TargetGroup  = aws_lb_target_group.backend.arn_suffix
        LoadBalancer = aws_lb.api.arn_suffix
      }
    }
  }
  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      period      = 300
      stat        = "Sum"
      dimensions = {
        TargetGroup  = aws_lb_target_group.backend.arn_suffix
        LoadBalancer = aws_lb.api.arn_suffix
      }
    }
  }
}

# 2. High p99 latency on the ALB target group (>2s for 5 minutes).
resource "aws_cloudwatch_metric_alarm" "alb_p99_latency" {
  alarm_name          = "${local.name_prefix}-alb-p99-latency"
  alarm_description   = "ALB target p99 latency above 2 seconds for 5 minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p99"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 300
  threshold           = 2.0
  treat_missing_data  = "notBreaching"
  dimensions = {
    TargetGroup  = aws_lb_target_group.backend.arn_suffix
    LoadBalancer = aws_lb.api.arn_suffix
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
}

# 3. RDS DB connection saturation (>60 connections sustained for 5 min, ≈75% of t4g.micro cap).
resource "aws_cloudwatch_metric_alarm" "rds_connection_saturation" {
  alarm_name          = "${local.name_prefix}-rds-connections"
  alarm_description   = "RDS DB connections above 60 (≈75% of t4g.micro cap) for 5 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 300
  threshold           = 60
  treat_missing_data  = "notBreaching"
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
}

# 4. ECS service deployment failure (deployment circuit breaker tripped).
resource "aws_cloudwatch_metric_alarm" "ecs_deployment_failed" {
  alarm_name          = "${local.name_prefix}-ecs-deployment-failed"
  alarm_description   = "ECS deployment circuit breaker tripped (rollback)."
  namespace           = "AWS/ECS"
  metric_name         = "DeploymentFailureCount"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 60
  threshold           = 0
  treat_missing_data  = "notBreaching"
  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.backend.name
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
}

# 5. RDS storage utilization > 85% (free below 15% of allocated).
resource "aws_cloudwatch_metric_alarm" "rds_low_disk" {
  alarm_name          = "${local.name_prefix}-rds-low-disk"
  alarm_description   = "RDS free storage below 15% of allocated capacity."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Average"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  period              = 300
  threshold           = aws_db_instance.postgres.allocated_storage * 1024 * 1024 * 1024 * 0.15
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
}

# 6. EventBridge scheduler DLQ depth — moved from scheduler.tf for cohesion.
#    Same threshold/dimensions as before; routes to SNS now.
resource "aws_cloudwatch_metric_alarm" "scheduler_dlq_depth" {
  alarm_name          = "${local.name_prefix}-scheduler-dlq-depth"
  alarm_description   = "EventBridge scheduler DLQ has visible messages — a schedule failed to deliver."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 60
  threshold           = 0
  treat_missing_data  = "notBreaching"
  dimensions = {
    QueueName = aws_sqs_queue.scheduler_dlq.name
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
}
