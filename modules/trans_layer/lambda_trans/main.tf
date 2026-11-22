resource "aws_lambda_function" "catalog_manager" {
  function_name = var.function_name

  package_type = "Image"

  image_uri = "${aws_ecr_repository.catalog_manager.repository_url}@${docker_registry_image.catalog_manager.sha256_digest}"

  role = aws_iam_role.lambda_role.arn

  # reads one parquet footer per call; the trigger Lambda waits for it
  timeout     = 60
  memory_size = 1024

  architectures = ["x86_64"]

  environment {
    variables = {
      RAW_BUCKET_NAME = var.raw_bucket_name
      DATABASE_NAME   = var.raw_database_name
      RAW_PREFIX      = var.raw_prefix
      SOURCE_SCHEMA   = var.source_schema
      TABLES          = join(",", var.table_names)
    }
  }

  depends_on = [
    aws_iam_role_policy.s3_read,
    aws_iam_role_policy.glue_catalog_access,
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.catalog_manager
  ]
}