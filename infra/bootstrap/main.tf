# ---------------------------------------------------------------------------
# State backend bootstrap (run ONCE, before migrating the main config's state).
#
# This is a SEPARATE Terraform config with its own LOCAL state. It creates the
# S3 bucket that the main config in ../ uses as its remote backend. Keeping it
# separate avoids the chicken-and-egg problem of a config trying to store its
# state in a bucket it hasn't created yet.
#
# Usage:
#   cd bootstrap
#   terraform init
#   terraform apply
#   # then uncomment the backend block in ../backend.tf and run:
#   cd .. && terraform init -migrate-state
# ---------------------------------------------------------------------------

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

resource "aws_s3_bucket" "state" {
  bucket = "${var.project_name}-tfstate-${var.aws_region}"

  # State is critical and irreplaceable; prevent accidental terraform destroy.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Terraform   = "true"
    Purpose     = "terraform-remote-state"
    Environment = "dev"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "aws-llm"
}

output "state_bucket" {
  description = "Name of the S3 bucket for Terraform remote state"
  value       = aws_s3_bucket.state.id
}
