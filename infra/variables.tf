variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Name of the project"
  default     = "aws-llm"
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
  default     = "aws-llm-eks"
}

variable "alert_email" {
  type        = string
  description = "Email address subscribed to the monitoring alarms SNS topic"
  default     = "lavale889@gmail.com"
}

