variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "crawler_name" {
  type    = string
  default = "stock-bronze-crawler"
}
