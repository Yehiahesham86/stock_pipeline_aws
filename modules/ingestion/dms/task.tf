
resource "aws_dms_replication_task" "stock" {
  replication_task_id = "stock-pipeline-replication"
  migration_type      = "full-load-and-cdc"

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
        "rule-name" = "include-app-tables"

        # every table in the app schema: teachers, students, class_bookings, payments, referrals
        "object-locator" = {
          "schema-name" = var.source_schema
          "table-name"  = "%"
        }

        "rule-action" = "include"
      },
      {
        # change order inside one commit (tie-break when dms_ts is equal)
        "rule-type"   = "transformation"
        "rule-id"     = "2"
        "rule-name"   = "add-change-seq"
        "rule-target" = "column"

        "object-locator" = {
          "schema-name" = var.source_schema
          "table-name"  = "%"
        }

        "rule-action" = "add-column"
        "value"       = "dms_change_seq"
        "expression"  = "$AR_H_CHANGE_SEQ"

        "data-type" = {
          "type"   = "string"
          "length" = 50
        }
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

