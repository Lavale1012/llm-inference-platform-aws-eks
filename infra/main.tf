terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
provider "aws" {
  region = var.aws_region
}

module "storage" {
  source = "./modules/storage"

  bucket_name   = "${var.project_name}-alb-logs"
  force_destroy = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Project     = var.project_name
  }
}

module "networking" {
  source = "./modules/networking"

  project_name        = var.project_name
  vpc_cidr            = "10.0.0.0/16"
  private_subnet_cidr = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnet_cidr  = ["10.0.10.0/24", "10.0.11.0/24"]
  az_range            = ["us-east-1a", "us-east-1b"]

  cluster_name = var.cluster_name
}
