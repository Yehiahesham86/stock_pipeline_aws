
output "athena_workgroup_name" {
  value = aws_athena_workgroup.stock_pipeline.name
}

output "athena_workgroup_arn" {
  value = aws_athena_workgroup.stock_pipeline.arn
}

output "athena_results_location" {
  value = "s3://${var.bronze_bucket_name}/${var.athena_results_prefix}"
}
