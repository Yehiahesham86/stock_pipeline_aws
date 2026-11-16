variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "crawler_name" {
  type    = string
  default = "stock-bronze-crawler"
}

# ---------- inputs wired from the root module ----------

variable "bronze_bucket_name" {
  description = "Bronze bucket name from module.s3_bronze"
  type        = string
}

variable "bronze_bucket_arn" {
  description = "Bronze bucket ARN from module.s3_bronze"
  type        = string
}

variable "bronze_prefix" {
  description = "Bronze prefix from module.s3_bronze"
  type        = string
}

variable "bronze_database_name" {
  description = "Bronze Glue database from module.glue_data_catalog"
  type        = string
}
