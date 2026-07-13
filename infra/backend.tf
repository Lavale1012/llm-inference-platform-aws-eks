# Remote state backend for the main infra config.
#
# PREREQUISITE: run the ./bootstrap config first to create the state bucket.
# Then uncomment this block and run:  terraform init -migrate-state
# (Terraform will move the existing local state into S3.)
#
# Uses S3 native locking (use_lockfile) — supported by AWS provider >= 5, so no
# DynamoDB table is required.

# terraform {
#   backend "s3" {
#     bucket       = "aws-llm-tfstate-us-east-1"
#     key          = "infra/terraform.tfstate"
#     region       = "us-east-1"
#     encrypt      = true
#     use_lockfile = true
#   }
# }
