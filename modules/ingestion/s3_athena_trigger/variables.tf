variable "aws_region" {
  type        = string
  description = "AWS region"
}

# ---------- Raw bucket (from module.s3_raw) ----------
variable "raw_bucket_name" {
  type        = string
  description = "Raw S3 bucket name"
}

variable "raw_bucket_arn" {
  type        = string
  description = "Raw S3 bucket ARN"
}

variable "raw_prefix" {
  type        = string
  description = "Prefix DMS writes parquet files to"
}

# ---------- Bronze bucket (from module.s3_bronze) ----------
variable "bronze_bucket_arn" {
  type        = string
  description = "Bronze S3 bucket ARN (Iceberg data + Athena results)"
}

# ---------- Athena (from module.athena) ----------
variable "athena_workgroup_name" {
  type        = string
  description = "Existing Athena workgroup"
}

variable "athena_workgroup_arn" {
  type        = string
  description = "Existing Athena workgroup ARN"
}

# ---------- Glue (from module.glue_data_catalog) ----------
variable "bronze_database_name" {
  type        = string
  description = "Glue database of the Bronze Iceberg table"
}

variable "raw_database_name" {
  type        = string
  description = "Glue database of the Raw external table"
}

# ---------- Tables (from module.athena) ----------
variable "table_names" {
  type        = list(string)
  description = "Tables to load; same name in Raw and Bronze"
}

variable "source_schema" {
  type        = string
  description = "Postgres schema; DMS writes to <raw_prefix><schema>/<table>/"
}

variable "bronze_table_ddl" {
  type        = list(string)
  description = "CREATE TABLE ... ICEBERG per table (sql/create_bronze_table.sql)"
}

# ---------- catalog_manager (from module.lambda_trans) ----------
variable "catalog_manager_function_name" {
  type        = string
  description = "Lambda that creates / updates the Raw Glue table from a file"
}

variable "catalog_manager_function_arn" {
  type        = string
  description = "ARN of catalog_manager (for lambda:InvokeFunction)"
}

# ---------- Lambda / SQS ----------
variable "function_name" {
  type    = string
  default = "stock-raw-athena-trigger"
}

variable "lambda_timeout" {
  type        = number
  description = "Seconds; the Lambda waits for each Athena query to finish"
  default     = 300
}

variable "batch_size" {
  type = number
  # 1: a Lambda timeout then only retries the one file it was loading,
  # not files of the same batch that were already inserted
  description = "SQS messages per Lambda call"
  default     = 1
}

variable "max_concurrency" {
  type        = number
  description = "Max parallel Lambdas from SQS (AWS minimum is 2)"
  default     = 2
}

variable "max_receive_count" {
  type        = number
  description = "Failed tries before a message moves to the DLQ"
  # 5: room for Iceberg commit-conflict retries before a good file hits the DLQ
  default = 5
}
