variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "function_name" {
  type    = string
  default = "stock-bronze-catalog-manager"
}

# ---------- inputs wired from the root module ----------

# Owns the Raw tables: reads a real DMS parquet file, writes its schema
# to Glue (instead of a crawler). Called by the trigger Lambda per new file.
# Bronze is an Iceberg table made by Athena.

variable "raw_bucket_name" {
  description = "Raw bucket name from module.s3_raw"
  type        = string
}

variable "raw_bucket_arn" {
  description = "Raw bucket ARN from module.s3_raw"
  type        = string
}

variable "raw_prefix" {
  description = "Prefix DMS writes to, e.g. raw/ (from module.s3_raw)"
  type        = string
}

variable "source_schema" {
  description = "Postgres schema; DMS writes to <raw_prefix><schema>/<table>/ (from module.athena)"
  type        = string
}

variable "raw_database_name" {
  description = "Raw Glue database from module.glue_data_catalog"
  type        = string
}

variable "table_names" {
  description = "Tables to catalog; same name in Raw and Bronze (from module.athena)"
  type        = list(string)
}
