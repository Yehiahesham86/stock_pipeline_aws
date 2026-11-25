# ==========================================
# Gold bucket: the 4 business tables built by dbt (Iceberg, through Athena CTAS).
# Layout written by dbt-athena: iceberg/<schema>/<table>/<uuid>/
#   (unique folder per build, so a rebuild never mixes with old files)
# No versioning: Gold is rebuilt from Silver on every run, old versions are waste.
# ==========================================

resource "aws_s3_bucket" "gold" {
  bucket        = var.gold_bucket_name
  force_destroy = true

  tags = {
    Project = "TutoringPipeline"
    Layer   = "Gold"
  }
}

resource "aws_s3_bucket_versioning" "gold" {
  bucket = aws_s3_bucket.gold.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "gold" {
  bucket = aws_s3_bucket.gold.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "gold" {
  bucket = aws_s3_bucket.gold.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# a CTAS that dies mid-write leaves multipart uploads behind (billed, invisible)
resource "aws_s3_bucket_lifecycle_configuration" "gold" {
  bucket = aws_s3_bucket.gold.id

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}
