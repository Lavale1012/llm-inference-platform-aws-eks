variable "project_name" {
  type        = string
  description = "Name of the project; used as a prefix for alarm and topic names"
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster the node alarms watch"
}

variable "alert_email" {
  type        = string
  description = "Email address subscribed to the alarms SNS topic"
}

variable "cost_threshold_usd" {
  type        = number
  description = "Estimated-charges threshold (USD) that triggers the billing alarm"
  default     = 80
}

variable "node_cpu_threshold" {
  type        = number
  description = "EKS node CPU utilization percentage that triggers the CPU alarm"
  default     = 80
}

variable "node_memory_threshold" {
  type        = number
  description = "EKS node memory utilization percentage that triggers the memory alarm"
  default     = 80
}

variable "alb_arn_suffix" {
  type        = string
  description = "ARN suffix of the LLM ALB (e.g. app/my-alb/abc123). Leave empty to skip the ALB 5xx alarm until the Ingress/ALB exists."
  default     = ""
}

variable "alb_5xx_threshold" {
  type        = number
  description = "Number of ALB 5xx responses in a period that triggers the alarm"
  default     = 10
}
