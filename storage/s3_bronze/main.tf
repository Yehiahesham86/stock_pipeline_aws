terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Define variables for the S3 bucket name and AWS region
provider "aws" {
  region = var.aws_region
}

# Create an S3 bucket for the bronze layer
resource "aws_s3_bucket" "bronze" {
  bucket = var.bucket_name

  tags = {
    Name        = "Stock Data Bronze"
    Environment = "Development"
    Project     = "StockDataPipeline"
  }
  force_destroy = true
}

# Enable versioning for the S3 bucket
resource "aws_s3_bucket_versioning" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  versioning_configuration {
    status = "Disabled"
  }
}

# Block public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable server-side encryption for the S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bronze layer folder
resource "aws_s3_object" "bronze_folder" {
  bucket = aws_s3_bucket.bronze.id
  key    = "bronze/"
}