
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_ecr_repository" "lambda" {
  name                 = "stock-bronze-catalog-manager"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_lambda_function" "catalog_manager" {
  function_name = var.function_name

  package_type = "Image"

  image_uri = "${aws_ecr_repository.lambda.repository_url}:v1"

  role = aws_iam_role.lambda_role.arn

  timeout     = 300
  memory_size = 1024

  architectures = ["x86_64"]

  environment {
    variables = {
      BUCKET_NAME  = var.bucket_name
      DATABASE_NAME = var.database_name
      TABLE_NAME   = "stock_prices"
      S3_PREFIX    = "bronze/"
    }
  }

  depends_on = [
    aws_iam_role_policy.s3_read,
    aws_iam_role_policy.glue_catalog_access,
    aws_iam_role_policy_attachment.lambda_logs
  ]
}
