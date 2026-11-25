variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "raw_bucket_name" {
  type        = string
  description = "stock_price_s3_raw_pipeline"
  default     = "stock-raw-unique-yh-toutoring-1345"
}
