
output "athena_workgroup_name" {
  value = aws_athena_workgroup.stock_pipeline.name
}

output "athena_workgroup_arn" {
  value = aws_athena_workgroup.stock_pipeline.arn
}

output "athena_results_location" {
  value = "s3://${var.bronze_bucket_name}/${var.athena_results_prefix}"
}

# The 5 tutoring tables (same name in Raw and Bronze)
output "table_names" {
  value = keys(local.tables)
}

# Postgres schema; DMS writes to <raw_prefix><source_schema>/<table>/
output "source_schema" {
  value = var.source_schema
}

# Rendered Bronze DDL (list, one per table). The trigger Lambda runs it on apply.
output "bronze_table_ddl" {
  value = local.bronze_ddl
}
