
# PostgreSQL Source Endpoint

resource "aws_dms_endpoint" "postgres_source" {
  endpoint_id   = "stock-postgres-source"
  endpoint_type = "source"
  engine_name   = "postgres"

  server_name   = var.source_host
  port          = var.source_port
  database_name = var.database_name
  username      = var.database_username
  password      = var.database_password

  ssl_mode = "none"

  tags = {
    Project = "StockDataPipeline"
  }
}


# S3 Target Endpoint

resource "aws_dms_s3_endpoint" "s3_target" {
  endpoint_id   = "stock-s3-raw-target"
  endpoint_type = "target"

  bucket_name = var.raw_bucket_name
  # "raw/" -> "raw": DMS adds its own "/" before schema/table
  bucket_folder           = trimsuffix(var.raw_prefix, "/")
  service_access_role_arn = aws_iam_role.dms_s3_access.arn

  data_format      = "parquet"
  compression_type = "GZIP"
  add_column_name  = true

  # CDC metadata columns in every file (Raw + Bronze tables expect them)
  include_op_for_full_load = true     # Op = I for full-load rows too
  timestamp_column_name    = "dms_ts" # source commit time

  date_partition_enabled   = true
  date_partition_sequence  = "YYYYMMDD"
  date_partition_delimiter = "SLASH"
  date_partition_timezone  = "UTC"
  tags = {
    Project = "StockDataPipeline"
  }

}
