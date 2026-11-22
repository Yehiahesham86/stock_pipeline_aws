# ==========================================
# Artifacts bucket: job code + Spark logs.
#   scripts/  <- upload the PySpark job here
#   logs/     <- EMR Serverless writes driver/executor logs here
# ==========================================

resource "aws_s3_bucket" "artifacts" {
  bucket        = var.artifacts_bucket_name
  force_destroy = true

  tags = {
    Project = "TutoringPipeline"
    Layer   = "Artifacts"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Spark logs pile up per run -> delete after a week
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    expiration {
      days = 7
    }
  }
}

# ---------- job code (jobs/) -> scripts/ ; etag = re-upload when the file changes ----------
resource "aws_s3_object" "job_entry_point" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "scripts/bronze_to_silver.py"
  source = "${path.module}/jobs/bronze_to_silver.py"
  etag   = filemd5("${path.module}/jobs/bronze_to_silver.py")
}

resource "aws_s3_object" "job_transforms" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "scripts/transforms.py"
  source = "${path.module}/jobs/transforms.py"
  etag   = filemd5("${path.module}/jobs/transforms.py")
}
