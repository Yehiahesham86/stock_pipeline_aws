output "ingestion_queue_arn" {
  value = aws_sqs_queue.ingestion.arn
}

output "ingestion_queue_url" {
  value = aws_sqs_queue.ingestion.url
}

output "ingestion_dlq_arn" {
  value = aws_sqs_queue.ingestion_dlq.arn
}
output "raw_event_rule_arn" {
  value = aws_cloudwatch_event_rule.raw_object_created.arn
}