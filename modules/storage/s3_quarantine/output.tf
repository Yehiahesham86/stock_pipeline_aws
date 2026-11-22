output "quarantine_bucket_name" {
  value = aws_s3_bucket.quarantine.bucket
}

output "quarantine_bucket_arn" {
  value = aws_s3_bucket.quarantine.arn
}
