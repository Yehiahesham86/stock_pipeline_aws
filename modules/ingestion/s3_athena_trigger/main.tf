# ==========================================
# IAM role for the Athena trigger Lambda
# ==========================================

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "athena_trigger" {
  # destroy also detaches policies attached outside Terraform
  force_detach_policies = true

  name = "stock-raw-athena-trigger-role"

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

# CloudWatch logs
resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.athena_trigger.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Read messages from the queue
resource "aws_iam_role_policy" "sqs" {
  name = "stock-raw-athena-trigger-sqs"
  role = aws_iam_role.athena_trigger.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ]

      Resource = aws_sqs_queue.raw_events.arn
    }]
  })
}

# Run queries in the existing Athena workgroup
resource "aws_iam_role_policy" "athena" {
  name = "stock-raw-athena-trigger-athena"
  role = aws_iam_role.athena_trigger.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "athena:StartQueryExecution",
        "athena:GetQueryExecution",
        "athena:GetQueryResults",
        "athena:GetWorkGroup"
      ]

      Resource = var.athena_workgroup_arn
    }]
  })
}

# Athena uses the Lambda's role to read the Glue tables
resource "aws_iam_role_policy" "glue" {
  name = "stock-raw-athena-trigger-glue"
  role = aws_iam_role.athena_trigger.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "glue:GetDatabase",
        "glue:GetTable",
        "glue:CreateTable",
        "glue:UpdateTable",
        "glue:GetPartition",
        "glue:GetPartitions",
        "glue:BatchGetPartition"
      ]

      Resource = [
        "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
        "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${var.raw_database_name}",
        "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.raw_database_name}/*",
        "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${var.bronze_database_name}",
        "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.bronze_database_name}/*"
      ]
    }]
  })
}

# Athena also uses the role for S3:
#   read Raw parquet, write Bronze Iceberg files + query results
resource "aws_iam_role_policy" "s3" {
  name = "stock-raw-athena-trigger-s3"
  role = aws_iam_role.athena_trigger.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]

        Resource = [
          var.raw_bucket_arn,
          var.bronze_bucket_arn
        ]
      },
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject"
        ]

        Resource = "${var.raw_bucket_arn}/${var.raw_prefix}*"
      },
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload"
        ]

        Resource = "${var.bronze_bucket_arn}/*"
      }
    ]
  })
}

# Call catalog_manager (creates / updates the Raw table) before each INSERT
resource "aws_iam_role_policy" "invoke_catalog_manager" {
  name = "stock-raw-athena-trigger-invoke-catalog"
  role = aws_iam_role.athena_trigger.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = var.catalog_manager_function_arn
    }]
  })
}
