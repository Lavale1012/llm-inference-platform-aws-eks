output "sns_topic_arn" {
  description = "ARN of the SNS topic all alarms notify"
  value       = aws_sns_topic.alarms.arn
}

output "billing_alarm_arn" {
  description = "ARN of the billing/cost alarm"
  value       = module.billing_alarm.cloudwatch_metric_alarm_arn
}
