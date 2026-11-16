variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bronze_bucket_name" {
  description = "stock_price_s3_bronze_pipeline"
  type        = string
  default     = "stock-bronze-unique123"
}