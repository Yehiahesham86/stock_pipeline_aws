# IAM Role
resource "aws_iam_role" "crawler_role" {
  name = "stock-bronze-crawler-role"

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

# Glue Service Permissions
resource "aws_iam_role_policy_attachment" "glue_service" {
  role = aws_iam_role.crawler_role.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# S3 Read Permissions
resource "aws_iam_role_policy" "s3_access" {
  name = "stock-bronze-crawler-s3-read"
  role = aws_iam_role.crawler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}/bronze/*"
      }
    ]
  })
}
