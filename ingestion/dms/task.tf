
resource "aws_dms_replication_task" "stock" {
  replication_task_id      = "stock-pipeline-replication"
  migration_type           = "full-load-and-cdc"

  replication_instance_arn = aws_dms_replication_instance.stock.replication_instance_arn

  source_endpoint_arn = aws_dms_endpoint.postgres_source.endpoint_arn
  target_endpoint_arn = aws_dms_s3_endpoint.s3_target.endpoint_arn
  #replecation logging
  replication_task_settings = jsonencode({
  Logging = {
    EnableLogging = true
  }
  })

  table_mappings = jsonencode({
    rules = [
      {
        "rule-type" = "selection"
        "rule-id"   = "1"
        "rule-name" = "include-stock-prices"

        "object-locator" = {
          "schema-name" = "public"
          "table-name"  = "stock_prices"
        }

        "rule-action" = "include"
      }
    ]
  })

  start_replication_task = false

  tags = {
    Name    = "stock-pipeline-replication"
    Project = "StockDataPipeline"
  }
}

output "replication_task_arn" {
  description = "ARN of the stock replication task"
  value       = aws_dms_replication_task.stock.replication_task_arn
}

output "replication_task_status" {
  description = "Status of the stock replication task"
  value       = aws_dms_replication_task.stock.status
}

