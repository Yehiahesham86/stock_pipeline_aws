output "glue_etl_role_arn" {
  value = aws_iam_role.glue_etl.arn
}
output "glue_job_name" {
  value = aws_glue_job.bronze_to_silver.name
}