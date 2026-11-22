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

# query in Athena: SELECT * FROM stock_quarantine.students
output "quarantine_tables" {
  value = module.athena.quarantine_table_names
}

output "spark_log_group_name" {
  value = module.spark_ecs.log_group_name
}

# start a run by hand: aws stepfunctions start-execution --state-machine-arn <this>
output "pipeline_state_machine_arn" {
  value = module.pipeline_run.state_machine_arn
}
