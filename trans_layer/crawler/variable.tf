variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  type    = string
  default = "stock-bronze-unique123"
}

variable "database_name" {
  type    = string
  default = "stock_bronze"
}

variable "crawler_name" {
  type    = string
  default = "stock-bronze-crawler"
}
