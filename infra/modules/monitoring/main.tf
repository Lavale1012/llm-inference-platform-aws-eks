# SNS topic that all alarms notify. The email endpoint must confirm the
# subscription (one-time link) before notifications are delivered.
resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-alarms"

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# Cost / billing alarm
# ---------------------------------------------------------------------------
# NOTE: The AWS/Billing EstimatedCharges metric is only published in us-east-1,
# is denominated in USD (unit "None"), requires the Currency dimension, and
# updates roughly every 6h — hence the 6h period.
module "billing_alarm" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.0"

  alarm_name          = "${var.project_name}-high-cost"
  alarm_description   = "Estimated AWS charges exceeded $${var.cost_threshold_usd}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  period              = 21600 # 6 hours
  threshold           = var.cost_threshold_usd
  unit                = "None"

  namespace   = "AWS/Billing"
  metric_name = "EstimatedCharges"
  statistic   = "Maximum"
  dimensions = {
    Currency = "USD"
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# ---------------------------------------------------------------------------
# EKS node health alarms
# ---------------------------------------------------------------------------
# Node CPU/memory come from the CloudWatch agent / Container Insights
# (namespace ContainerInsights), keyed by ClusterName. These require Container
# Insights to be enabled on the cluster to report data.
module "node_cpu_alarm" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.0"

  alarm_name          = "${var.cluster_name}-node-cpu-high"
  alarm_description   = "EKS node CPU utilization is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  period              = 300
  threshold           = var.node_cpu_threshold
  unit                = "Percent"

  namespace   = "ContainerInsights"
  metric_name = "node_cpu_utilization"
  statistic   = "Average"
  dimensions = {
    ClusterName = var.cluster_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

module "node_memory_alarm" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.0"

  alarm_name          = "${var.cluster_name}-node-memory-high"
  alarm_description   = "EKS node memory utilization is high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  period              = 300
  threshold           = var.node_memory_threshold
  unit                = "Percent"

  namespace   = "ContainerInsights"
  metric_name = "node_memory_utilization"
  statistic   = "Average"
  dimensions = {
    ClusterName = var.cluster_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# ---------------------------------------------------------------------------
# LLM-serving ALB alarm
# ---------------------------------------------------------------------------
# The ALB is created dynamically by the AWS Load Balancer Controller, so its
# ARN suffix is only known at runtime. This alarm is created only when
# var.alb_arn_suffix is supplied (e.g. after the Ingress exists).
module "alb_5xx_alarm" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.0"

  count = var.alb_arn_suffix == "" ? 0 : 1

  alarm_name          = "${var.project_name}-alb-5xx-high"
  alarm_description   = "ALB is returning elevated 5xx errors (LLM service unhealthy)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  period              = 300
  threshold           = var.alb_5xx_threshold

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"
  statistic   = "Sum"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}
