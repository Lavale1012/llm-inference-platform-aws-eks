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

variable "github_repository" {
  type        = string
  description = "GitHub repo (owner/name) allowed to assume the CI/CD OIDC role"
  default     = "Lavale1012/llm-inference-platform-aws-eks"
}

variable "ecr_push_role_arns" {
  type        = list(string)
  description = "Extra IAM role ARNs granted push access to the ECR repository (in addition to the CI/CD role, which is added automatically)"
  default     = []
}

