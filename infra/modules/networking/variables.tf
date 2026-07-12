variable "project_name" {
  type        = string
  description = "Name of the project"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
}

variable "private_subnet_cidr" {
  type        = list(string)
  description = "CIDR blocks for private subnets"
}

variable "public_subnet_cidr" {
  type        = list(string)
  description = "CIDR blocks for public subnets"
}

variable "az_range" {
  type        = list(string)
  description = "range of AZs"
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster; used to tag subnets for the AWS Load Balancer Controller"
}
