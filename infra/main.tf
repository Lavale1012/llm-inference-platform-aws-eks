terraform {
  # Pinned to match CI (GitHub Actions uses Terraform 1.9.x) so local and
  # pipeline runs resolve the same CLI behaviour.
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Authenticate the kubernetes/helm providers against the EKS cluster.
data "aws_eks_cluster_auth" "this" {
  name = module.compute.cluster_name
}

provider "kubernetes" {
  host                   = module.compute.cluster_endpoint
  cluster_ca_certificate = base64decode(module.compute.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = module.compute.cluster_endpoint
    cluster_ca_certificate = base64decode(module.compute.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
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

module "compute" {
  source = "./modules/compute"

  cluster_name             = var.cluster_name
  kubernetes_version       = "1.33"
  aws_region               = var.aws_region
  vpc_id                   = module.networking.vpc_id
  subnet_ids               = module.networking.private_subnets
  control_plane_subnet_ids = module.networking.private_subnets
  ami                      = "AL2023_x86_64_STANDARD"
  instance_types           = ["m5.xlarge"]
  min_size                 = 2
  max_size                 = 10
  desired_size             = 2
  repository_name          = var.project_name

  # Grant the GitHub Actions CI role push access to ECR (repository policy) and
  # kubectl access to the cluster (EKS access entry). Any extra ARNs supplied
  # via var.ecr_push_role_arns are appended to the ECR push list.
  ci_role_arn        = aws_iam_role.github_actions.arn
  ecr_push_role_arns = concat([aws_iam_role.github_actions.arn], var.ecr_push_role_arns)
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name = var.project_name
  cluster_name = var.cluster_name
  alert_email  = var.alert_email
}
