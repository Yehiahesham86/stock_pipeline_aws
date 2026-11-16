variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# No default. Set it before running:
#   export TF_VAR_database_password=...
variable "database_password" {
  description = "PostgreSQL password for DMS"
  type        = string
  sensitive   = true
}
