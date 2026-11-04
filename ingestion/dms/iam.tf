
resource "aws_iam_role" "dms_s3_access" {
  name = "stock-pipeline-dms-s3-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "dms.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = "StockDataPipeline"
  }
}

resource "aws_iam_role_policy" "dms_s3_access" {
  name = "stock-pipeline-dms-s3-write"
  role = aws_iam_role.dms_s3_access.id

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Sid" : "BucketAccess",
          "Effect" : "Allow",
          "Action" : [
            "s3:ListBucket",
            "s3:GetBucketLocation"
          ],
          "Resource" : "arn:aws:s3:::stock-bronze-unique123"
        },
        {
          "Sid" : "ObjectAccess",
          "Effect" : "Allow",
          "Action" : [
            "s3:PutObject",
            "s3:GetObject",
            "s3:DeleteObject",
            "s3:AbortMultipartUpload"
          ],
          "Resource" : "arn:aws:s3:::stock-bronze-unique123/bronze/*"
        }
      ]
    }
  )
}

resource "aws_iam_role" "dms_vpc" {
  name        = "dms-vpc-role"
  description = "Allows AWS DMS to manage VPC networking"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "dms.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = "StockDataPipeline"
  }
}

resource "aws_iam_role_policy_attachment" "dms_vpc" {
  role = aws_iam_role.dms_vpc.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}