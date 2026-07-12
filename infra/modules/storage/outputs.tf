output "bucket_id" {
  description = "The name (ID) of the S3 bucket"
  value       = module.s3_bucket_for_logs.s3_bucket_id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = module.s3_bucket_for_logs.s3_bucket_arn
}

output "bucket_domain_name" {
  description = "The bucket domain name (bucket.s3.amazonaws.com)"
  value       = module.s3_bucket_for_logs.s3_bucket_bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The regional domain name of the bucket"
  value       = module.s3_bucket_for_logs.s3_bucket_bucket_regional_domain_name
}
