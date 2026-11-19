
variable "bronze_bucket_name" {
  type        = string
  description = "Bronze S3 bucket name"
}

variable "athena_results_prefix" {
  type        = string
  description = "S3 prefix for Athena query execution results"
  default     = "athena-results/"
}

# ---------- Bronze table DDL (sql/create_bronze_table.sql) ----------

variable "bronze_database_name" {
  type        = string
  description = "Glue Bronze database (from module.glue_data_catalog)"
}

variable "source_schema" {
  type        = string
  description = "Postgres schema; DMS writes to <raw_prefix><schema>/<table>/"
  default     = "app"
}

variable "bronze_iceberg_prefix" {
  type        = string
  description = "S3 prefix in the Bronze bucket for Iceberg tables"
  default     = "iceberg/"
}
