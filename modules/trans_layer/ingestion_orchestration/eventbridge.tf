
resource "aws_cloudwatch_event_rule" "raw_object_created" {
  name        = "stock-raw-object-created"
  description = "Detect new DMS files in the Raw S3 bucket"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]

    detail = {
      bucket = {
        name = [var.raw_bucket_name]
      }

      object = {
        key = [
          {
            prefix = var.raw_prefix
          }
        ]
      }
    }
  })

  tags = {
    Project = "StockDataPipeline"
    Layer   = "Ingestion"
  }
}

resource "aws_cloudwatch_event_target" "raw_to_sqs" {
  rule      = aws_cloudwatch_event_rule.raw_object_created.name
  target_id = "StockIngestionQueue"
  arn       = aws_sqs_queue.ingestion.arn
}

resource "aws_sqs_queue_policy" "allow_eventbridge" {
  queue_url = aws_sqs_queue.ingestion.url

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowEventBridge"
        Effect = "Allow"

        Principal = {
          Service = "events.amazonaws.com"
        }

        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.ingestion.arn

        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.raw_object_created.arn
          }
        }
      }
    ]
  })
}
