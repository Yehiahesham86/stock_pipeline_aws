variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "database_name" {
  description = "Glue Data Catalog database name"
  type        = string
  default     = "stock_bronze"
}