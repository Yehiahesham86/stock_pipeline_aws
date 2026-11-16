resource "aws_lambda_function" "catalog_manager" {
  function_name = var.function_name

  package_type = "Image"

  image_uri = "${aws_ecr_repository.catalog_manager.repository_url}@${docker_registry_image.catalog_manager.sha256_digest}"

  role = aws_iam_role.lambda_role.arn

  timeout     = 300
  memory_size = 1024

  architectures = ["x86_64"]

  environment {
    variables = {
      bronze_bucket_name = var.bronze_bucket_name
      DATABASE_NAME      = var.bronze_database_name
      TABLE_NAME         = "stock_prices"
      S3_PREFIX          = var.bronze_prefix
    }
  }

  depends_on = [
    aws_iam_role_policy.s3_read,
    aws_iam_role_policy.glue_catalog_access,
    aws_iam_role_policy_attachment.lambda_logs
  ]
}