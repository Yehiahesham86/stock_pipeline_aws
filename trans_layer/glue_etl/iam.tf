resource "aws_iam_role" "glue_etl" {
  name = "stock-pipeline-glue-etl-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "glue.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_etl.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_catalog" {
  name = "stock-pipeline-glue-s3-catalog"
  role = aws_iam_role.glue_etl.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BronzeRead"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = data.terraform_remote_state.s3_bronze.outputs.bronze_bucket_arn
      },
      {
        Sid    = "BronzeObjectsRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${data.terraform_remote_state.s3_bronze.outputs.bronze_bucket_arn}/*"
      },
      {
        Sid    = "SilverBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = data.terraform_remote_state.s3_silver.outputs.silver_bucket_arn
      },
      {
        Sid    = "SilverObjectsAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${data.terraform_remote_state.s3_silver.outputs.silver_bucket_arn}/*"
      },
      {
        Sid    = "GlueCatalogAccess"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:BatchCreatePartition",
          "glue:BatchDeletePartition",
          "glue:GetPartition",
          "glue:GetPartitions"
        ]
        Resource = "*"
      }
    ]
  })
}