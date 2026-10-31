output "bucket_name" {
  value = aws_s3_bucket.bronze.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.bronze.arn
}

output "bronze_prefix" {
  value = aws_s3_object.bronze_folder.key
}