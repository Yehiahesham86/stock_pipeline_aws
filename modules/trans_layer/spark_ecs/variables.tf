variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "name" {
  description = "Name for the ECR repo, ECS cluster, task family, roles, log group"
  type        = string
  default     = "tutoring-bronze-to-silver"
}

# Fargate: 1 vCPU allows 2-8 GB. 3 GB = 2 GB Spark JVM + room for Python workers
variable "task_cpu" {
  description = "Fargate CPU units (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "task_memory" {
  description = "Fargate memory in MiB"
  type        = number
  default     = 3072
}

variable "driver_memory" {
  description = "Spark driver JVM heap (local mode: driver = executor)"
  type        = string
  default     = "2g"
}

# ---------- wired from other modules in the root main.tf ----------
variable "vpc_id" {
  type = string
}

variable "bronze_bucket_arn" {
  type = string
}

variable "silver_bucket_arn" {
  type = string
}

variable "quarantine_bucket_arn" {
  type = string
}

variable "bronze_database_name" {
  type = string
}

variable "silver_database_name" {
  type = string
}

# Silver Iceberg tables are created under s3://<silver bucket>/iceberg/
variable "silver_bucket_name" {
  type = string
}

variable "quarantine_bucket_name" {
  type = string
}

variable "table_names" {
  description = "Source tables the job processes"
  type        = list(string)
}
