provider "aws" {
  region = var.aws_region
}


# Glue Crawler
resource "aws_glue_crawler" "bronze" {
  name          = var.crawler_name
  role          = aws_iam_role.crawler_role.arn
  database_name = var.database_name

  s3_target {
    path = "s3://${var.bucket_name}/bronze/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  depends_on = [
    aws_iam_role_policy_attachment.glue_service,
    aws_iam_role_policy.s3_access
  ]
}