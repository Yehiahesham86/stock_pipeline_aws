output "raw_events_queue_url" {
  value = aws_sqs_queue.raw_events.url
}

output "raw_events_queue_arn" {
  value = aws_sqs_queue.raw_events.arn
}

output "raw_events_dlq_url" {
  value = aws_sqs_queue.raw_events_dlq.url
}

output "athena_trigger_function_name" {
  value = aws_lambda_function.athena_trigger.function_name
}
