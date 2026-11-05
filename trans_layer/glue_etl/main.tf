terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Define variables for the crawler bucket name and AWS region
provider "aws" {
  region = var.aws_region
}

resource "aws_s3_object" "glue_script" {
  bucket = data.terraform_remote_state.s3_silver.outputs.silver_bucket_name
  key    = "scripts/bronze_to_silver.py"

  source = "${path.module}/transformation_script/bronze_to_silver.py"
  etag   = filemd5("${path.module}/transformation_script/bronze_to_silver.py")
}

resource "aws_glue_job" "bronze_to_silver" {
  name     = var.glue_job_name
  role_arn = aws_iam_role.glue_etl.arn

  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_object.glue_script.bucket}/${aws_s3_object.glue_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--source_database"                  = data.terraform_remote_state.glue_catalog.outputs.bronze_database_name
    "--target_database"                  = data.terraform_remote_state.glue_catalog.outputs.silver_database_name
    "--target_path"                      = "s3://${data.terraform_remote_state.s3_silver.outputs.silver_bucket_name}/silver/"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  max_retries = 0
  timeout     = 30

  depends_on = [
    aws_iam_role_policy_attachment.glue_service,
    aws_iam_role_policy.glue_s3_catalog
  ]
}