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

