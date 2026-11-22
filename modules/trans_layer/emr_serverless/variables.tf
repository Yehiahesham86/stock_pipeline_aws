variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "application_name" {
  description = "EMR Serverless application name"
  type        = string
  default     = "tutoring-bronze-to-silver"
}

# EMR 7.x: Spark 3.5 + Iceberg bundled (/usr/share/aws/iceberg/lib/), same Spark
# line as the local Glue 5 image
variable "release_label" {
  description = "EMR release"
  type        = string
  default     = "emr-7.5.0"
}

# Cap for the whole application (all running jobs together)
variable "max_cpu" {
  description = "Max vCPU for the application"
  type        = string
  default     = "2 vCPU"
}

variable "max_memory" {
  description = "Max memory for the application"
  type        = string
  default     = "8 GB"
}

variable "artifacts_bucket_name" {
  description = "Bucket for job scripts and Spark logs"
  type        = string
  default     = "tutoring-emr-artifacts-unique12345"
}

# ---------- wired from other modules in the root main.tf ----------
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
