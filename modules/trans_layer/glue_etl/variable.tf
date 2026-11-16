variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "glue_job_name" {
  type    = string
  default = "stock-bronze-to-silver"
}

# ---------- inputs wired from the root module ----------

variable "bronze_bucket_arn" {
  description = "Bronze bucket ARN from module.s3_bronze"
  type        = string
}

variable "silver_bucket_name" {
  description = "Silver bucket name from module.s3_silver"
  type        = string
}

variable "silver_bucket_arn" {
  description = "Silver bucket ARN from module.s3_silver"
  type        = string
}

variable "bronze_database_name" {
  description = "Bronze Glue database from module.glue_data_catalog"
  type        = string
}

variable "silver_database_name" {
  description = "Silver Glue database from module.glue_data_catalog"
  type        = string
}
