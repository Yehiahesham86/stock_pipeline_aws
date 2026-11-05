variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "silver_bucket_name" {
  type    = string
  default = "stock-silver-unique123"
}
