output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.compute.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS control plane"
  value       = module.compute.cluster_endpoint
}

output "ecr_repository_url" {
  description = "URL of the ECR repository (docker push/pull target)"
  value       = module.compute.ecr_repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = module.compute.ecr_repository_arn
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role GitHub Actions assumes via OIDC (set as the AWS_CI_ROLE_ARN repo variable)"
  value       = aws_iam_role.github_actions.arn
}
