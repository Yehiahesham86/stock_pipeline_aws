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
# Task role: what dbt may touch. Athena reads and writes S3 / Glue with the
# caller's credentials, so these rights are also what Athena gets for dbt SQL:
#   Athena      run queries in the pipeline workgroup
#   Bronze      read (class_bookings delete events) + write Athena results
#   Silver      read
#   Gold        read + write + delete (CTAS; a rebuild drops the old table)
#   Glue        read Bronze/Silver, create/replace/drop tables in Gold
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
        Sid    = "AthenaQueries"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution",
          "athena:GetWorkGroup",
        ]
        Resource = var.athena_workgroup_arn
      },
      {
        Sid      = "AthenaCatalog"
        Effect   = "Allow"
        Action   = ["athena:GetDataCatalog"]
        Resource = "arn:aws:athena:${var.aws_region}:${data.aws_caller_identity.current.account_id}:datacatalog/AwsDataCatalog"
      },
      {
        Sid      = "ListBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [var.bronze_bucket_arn, var.silver_bucket_arn, var.gold_bucket_arn]
      },
      {
        Sid      = "ReadBronzeSilver"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${var.bronze_bucket_arn}/*", "${var.silver_bucket_arn}/*"]
      },
      {
        Sid      = "AthenaResults"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
        Resource = "${var.bronze_bucket_arn}/${var.athena_results_prefix}*"
      },
      {
        Sid      = "ReadWriteGold"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]
        Resource = "${var.gold_bucket_arn}/*"
      },
      {
        Sid    = "GlueCatalogRead"
        Effect = "Allow"
        Action = ["glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables", "glue:GetPartition", "glue:GetPartitions"]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${var.bronze_database_name}",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.bronze_database_name}/*",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${var.silver_database_name}",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.silver_database_name}/*",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${var.gold_database_name}",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.gold_database_name}/*",
        ]
      },
      {
        # dbt-athena table build: CTAS into a tmp table, swap names, drop the old one
        Sid    = "GlueCatalogWriteGold"
        Effect = "Allow"
        Action = [
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:DeleteTable",
          "glue:BatchDeleteTable",
          "glue:GetTableVersions",
          "glue:DeleteTableVersion",
          "glue:BatchDeleteTableVersion",
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${var.gold_database_name}",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.gold_database_name}/*",
        ]
      },
    ]
  })
}
