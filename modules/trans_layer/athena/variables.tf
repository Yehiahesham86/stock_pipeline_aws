
variable "bronze_bucket_name" {
  type        = string
  description = "Bronze S3 bucket name"
}

variable "athena_results_prefix" {
  type        = string
  description = "S3 prefix for Athena query execution results"
  default     = "athena-results/"
}

# ---------- table DDL (sql/*.sql templates) ----------

variable "raw_bucket_name" {
  type        = string
  description = "Raw S3 bucket name (from module.s3_raw)"
}

variable "raw_prefix" {
  type        = string
  description = "Prefix DMS writes to (from module.s3_raw)"
}

variable "raw_database_name" {
  type        = string
  description = "Glue Raw database (from module.glue_data_catalog)"
}

variable "bronze_database_name" {
  type        = string
  description = "Glue Bronze database (from module.glue_data_catalog)"
}

variable "table_name" {
  type        = string
  description = "Source table name; same name in Raw and Bronze"
  default     = "stock_prices"
}

variable "source_schema" {
  type        = string
  description = "Postgres schema; DMS writes to <raw_prefix><schema>/<table>/"
  default     = "public"
}

variable "bronze_iceberg_prefix" {
  type        = string
  description = "S3 prefix in the Bronze bucket for Iceberg tables"
  default     = "iceberg/"
}
