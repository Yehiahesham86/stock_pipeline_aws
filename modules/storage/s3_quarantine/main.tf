# ==========================================
# Quarantine bucket: rows that failed data quality in the Bronze -> Silver job.
# Layout written by the job: <table>/run_id=<id>/*.parquet
#   (the bad row + dq_errors column saying which rule failed)
# Not Iceberg: nobody MERGEs here, it's for inspection + re-feeding fixed rows.
# ==========================================

resource "aws_s3_bucket" "quarantine" {
  bucket        = var.quarantine_bucket_name
  force_destroy = true

  tags = {
    Project = "TutoringPipeline"
    Layer   = "Quarantine"
  }
}

resource "aws_s3_bucket_versioning" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bad rows are only kept long enough to look at them (free-tier storage)
resource "aws_s3_bucket_lifecycle_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    id     = "expire-quarantined-rows"
    status = "Enabled"

    filter {}

    expiration {
      days = var.quarantine_retention_days
    }
  }
}
