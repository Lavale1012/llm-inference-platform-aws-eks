variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version"
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs"
}

variable "control_plane_subnet_ids" {
  type        = list(string)
  description = "List of control plane subnet IDs"
}

variable "ami" {
  type        = string
  description = "AMI type"
}
variable "instance_types" {
  type        = list(string)
  description = "Size of instances"
}
variable "min_size" {
  type        = number
  description = "Minimum size of the node group"
}
variable "max_size" {
  type        = number
  description = "Maximum size of the node group"
}
variable "desired_size" {
  type        = number
  description = "Desired size of the node group"
}

# --- GPU node group (LLM inference) ---
variable "gpu_ami_type" {
  type        = string
  description = "AMI type for GPU nodes (NVIDIA-enabled)"
  default     = "AL2023_x86_64_NVIDIA"
}

variable "gpu_instance_types" {
  type        = list(string)
  description = "Instance types for GPU nodes"
  default     = ["g5.xlarge"]
}

variable "gpu_min_size" {
  type        = number
  description = "Minimum size of the GPU node group"
  default     = 0
}

variable "gpu_max_size" {
  type        = number
  description = "Maximum size of the GPU node group"
  default     = 2
}

variable "gpu_desired_size" {
  type        = number
  description = "Desired size of the GPU node group"
  default     = 1
}

variable "aws_region" {
  type        = string
  description = "AWS region the cluster runs in"
}

variable "aws_lb_controller_chart_version" {
  type        = string
  description = "Version of the aws-load-balancer-controller Helm chart"
  default     = "1.14.0"
}

variable "nvidia_device_plugin_chart_version" {
  type        = string
  description = "Version of the nvidia-device-plugin Helm chart"
  default     = "0.17.0"
}

variable "repository_name" {
  type        = string
  description = "Name of ECR repository"
}
variable "ecr_push_role_arns" {
  type        = list(string)
  description = "Additional IAM role ARNs (e.g. a CI/CD role) granted push access to the ECR repository"
  default     = []
}

variable "image_tag_mutability" {
  type        = string
  description = "ECR image tag mutability: MUTABLE or IMMUTABLE"
  default     = "IMMUTABLE"
}

variable "image_scan_on_push" {
  type        = bool
  description = "Scan images for vulnerabilities when pushed to ECR"
  default     = true
}
