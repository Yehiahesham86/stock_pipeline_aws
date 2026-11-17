variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "function_name" {
  type    = string
  default = "stock-bronze-catalog-manager"
}

# ---------- inputs wired from the root module ----------

# Catalogs the Raw table: reads a real DMS parquet file, writes its schema
# to Glue (instead of a crawler). Bronze is an Iceberg table made by Athena.

variable "raw_bucket_name" {
  description = "Raw bucket name from module.s3_raw"
  type        = string
}

variable "raw_bucket_arn" {
  description = "Raw bucket ARN from module.s3_raw"
  type        = string
}

variable "raw_table_prefix" {
  description = "Prefix of the DMS table files, e.g. raw/public/stock_prices/ (from module.athena)"
  type        = string
}

variable "raw_database_name" {
  description = "Raw Glue database from module.glue_data_catalog"
  type        = string
}

variable "table_name" {
  description = "Glue table to create/update (from module.athena)"
  type        = string
}
