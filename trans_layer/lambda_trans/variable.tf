variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  type    = string
  default = "stock-bronze-unique123"
}

variable "database_name" {
  type    = string
  default = "stock_bronze"
}

variable "function_name" {
  type    = string
  default = "stock-bronze-catalog-manager"
}