variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "glue_job_name" {
  type    = string
  default = "stock-bronze-to-silver"
}
