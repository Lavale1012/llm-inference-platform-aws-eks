variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket used for ALB/ELB access logs"
}

variable "force_destroy" {
  type        = bool
  description = "Allow deletion of the bucket even when it is not empty"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the bucket"
  default     = {}
}
