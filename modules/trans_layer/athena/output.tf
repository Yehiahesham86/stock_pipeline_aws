
output "athena_workgroup_name" {
  value = aws_athena_workgroup.stock_pipeline.name
}

output "athena_workgroup_arn" {
  value = aws_athena_workgroup.stock_pipeline.arn
}

output "athena_results_location" {
  value = "s3://${var.bronze_bucket_name}/${var.athena_results_prefix}"
}

output "table_name" {
  value = var.table_name
}

# Where DMS writes this table's files: raw/public/stock_prices/
output "raw_table_prefix" {
  value = "${var.raw_prefix}${var.source_schema}/${var.table_name}/"
}

# Rendered DDL. The trigger Lambda runs these in Athena on apply.
output "raw_table_ddl" {
  value = templatefile("${path.module}/sql/create_raw_table.sql", {
    raw_database = var.raw_database_name
    table        = var.table_name
    raw_location = "s3://${var.raw_bucket_name}/${var.raw_prefix}${var.source_schema}/${var.table_name}/"
  })
}

output "bronze_table_ddl" {
  value = templatefile("${path.module}/sql/create_bronze_table.sql", {
    bronze_database = var.bronze_database_name
    table           = var.table_name
    bronze_location = "s3://${var.bronze_bucket_name}/${var.bronze_iceberg_prefix}${var.table_name}/"
  })
}
