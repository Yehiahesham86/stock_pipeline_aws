# A module's outputs only show after apply if the root repeats them here.

output "bronze_bucket_name" {
  value = module.s3_bronze.bronze_bucket_name
}

output "silver_bucket_name" {
  value = module.s3_silver.silver_bucket_name
}


# apply.sh reads this to push the Lambda image.
output "ecr_repository_url" {
  value = module.lambda_trans.ecr_repository_url
}
