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

output "raw_events_queue_url" {
  value = module.s3_athena_trigger.raw_events_queue_url
}

output "raw_events_dlq_url" {
  value = module.s3_athena_trigger.raw_events_dlq_url
}

output "quarantine_bucket_name" {
  value = module.s3_quarantine.quarantine_bucket_name
}

output "emr_application_id" {
  value = module.emr_serverless.application_id
}

output "emr_job_role_arn" {
  value = module.emr_serverless.job_role_arn
}

output "emr_artifacts_bucket_name" {
  value = module.emr_serverless.artifacts_bucket_name
}

# start a run by hand: aws stepfunctions start-execution --state-machine-arn <this>
output "pipeline_state_machine_arn" {
  value = module.pipeline_run.state_machine_arn
}
