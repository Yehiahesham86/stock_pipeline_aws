#lambda role for glue catalog access and s3 access
resource "aws_iam_role" "lambda_role" {
  name = "stock-bronze-catalog-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "lambda.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })
}

#access to s3 bucket
resource "aws_iam_role_policy" "s3_read" {
  name = "stock-bronze-lambda-s3-read"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:ListBucket"
        ]

        Resource = data.terraform_remote_state.s3_bronze.outputs.bronze_bucket_arn
      },
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject"
        ]

        Resource = "${data.terraform_remote_state.s3_bronze.outputs.bronze_bucket_arn}/${data.terraform_remote_state.s3_bronze.outputs.bronze_prefix}*"
      }
    ]
  })
}

#access to glue catalog
data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "glue_catalog_access" {
  name = "stock-bronze-lambda-glue-access"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:GetPartitions",
          "glue:CreatePartition",
          "glue:BatchCreatePartition",
          "glue:BatchGetPartition"
        ]

        Resource = [
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${data.terraform_remote_state.glue_catalog.outputs.bronze_database_name}",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${data.terraform_remote_state.glue_catalog.outputs.bronze_database_name}/*"
        ]
      }
    ]
  })
}