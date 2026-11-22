data "aws_caller_identity" "current" {}

# ==========================================
# Execution role: what ECS itself needs to START the task
#   pull the image from ECR, write container logs
# ==========================================

resource "aws_iam_role" "execution" {
  # destroy also detaches policies attached outside Terraform
  force_detach_policies = true

  name = "${var.name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ==========================================
# Task role: what the Spark job itself may touch
#   Bronze      read            (Iceberg data + metadata)
#   Silver      read + write    (MERGE INTO Iceberg)
#   Quarantine  write           (bad rows)
#   Glue Catalog: read Bronze tables, create/update Silver tables
# ==========================================

resource "aws_iam_role" "task" {
  # destroy also detaches policies attached outside Terraform
  force_detach_policies = true

  name = "${var.name}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "task" {
  name = "${var.name}-task-policy"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [var.bronze_bucket_arn, var.silver_bucket_arn, var.quarantine_bucket_arn]
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
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]
        Resource = ["${var.silver_bucket_arn}/*"]
      },
      {
        Sid      = "WriteQuarantine"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]
        Resource = ["${var.quarantine_bucket_arn}/*"]
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
