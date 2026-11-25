variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "name" {
  description = "Name for the ECR repo, task family, roles, log group"
  type        = string
  default     = "tutoring-silver-to-gold"
}

# smallest Fargate size: dbt only waits on Athena
variable "task_cpu" {
  description = "Fargate CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate memory in MiB"
  type        = number
  default     = 512
}

variable "dbt_threads" {
  description = "Models dbt builds in parallel (each = 1 Athena query at a time)"
  type        = number
  default     = 4
}

# ---------- wired from other modules in the root main.tf ----------
variable "vpc_id" {
  type = string
}

variable "athena_workgroup_name" {
  type = string
}

variable "athena_workgroup_arn" {
  type = string
}

# the workgroup enforces its own result location; dbt-athena still requires one
variable "athena_results_location" {
  type = string
}

variable "athena_results_prefix" {
  description = "Prefix of the Athena results inside the Bronze bucket"
  type        = string
}

variable "bronze_bucket_arn" {
  type = string
}

variable "silver_bucket_arn" {
  type = string
}

variable "gold_bucket_arn" {
  type = string
}

# Gold Iceberg data goes under s3://<gold bucket>/iceberg/
variable "gold_bucket_name" {
  type = string
}

variable "bronze_database_name" {
  type = string
}

variable "silver_database_name" {
  type = string
}

variable "gold_database_name" {
  type = string
}
