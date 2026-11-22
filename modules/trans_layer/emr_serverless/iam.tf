# ==========================================
# Job execution role: what the Spark job itself may touch.
#   Bronze      read            (Iceberg data + metadata)
#   Silver      read + write    (MERGE INTO Iceberg)
#   Quarantine  write           (bad rows)
#   Artifacts   read scripts/, write logs/
#   Glue Catalog: read Bronze tables, create/update Silver tables
# ==========================================

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "emr_job" {
  # destroy also detaches policies attached outside Terraform
  force_detach_policies = true

  name = "${var.application_name}-job-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "emr-serverless.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "emr_job" {
  name = "${var.application_name}-job-policy"
  role = aws_iam_role.emr_job.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [var.bronze_bucket_arn, var.silver_bucket_arn, var.quarantine_bucket_arn, aws_s3_bucket.artifacts.arn]
      },
      {
        Sid      = "ReadBronze"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${var.bronze_bucket_arn}/*"]
      },
      {
        Sid      = "ReadWriteSilver"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${var.silver_bucket_arn}/*"]
      },
      {
        Sid      = "WriteQuarantine"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${var.quarantine_bucket_arn}/*"]
      },
      {
        Sid      = "ReadScripts"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.artifacts.arn}/scripts/*"]
      },
      {
        Sid      = "WriteLogs"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${aws_s3_bucket.artifacts.arn}/logs/*"]
      },
      {
        Sid    = "GlueCatalogRead"
        Effect = "Allow"
        Action = ["glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables", "glue:GetPartitions"]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${var.bronze_database_name}",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.bronze_database_name}/*",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${var.silver_database_name}",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.silver_database_name}/*",
        ]
      },
      {
        Sid    = "GlueCatalogWriteSilver"
        Effect = "Allow"
        Action = ["glue:CreateTable", "glue:UpdateTable"]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${var.silver_database_name}",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.silver_database_name}/*",
        ]
      },
    ]
  })
}
