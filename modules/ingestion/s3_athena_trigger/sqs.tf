# ==========================================
# DLQ: messages land here after max_receive_count failed tries
# ==========================================

resource "aws_sqs_queue" "raw_events_dlq" {
  name                      = "stock-raw-events-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Project = "StockDataPipeline"
    Layer   = "Raw"
  }
}

# ==========================================
# Main queue: S3 sends .parquet object-created events here
# ==========================================

resource "aws_sqs_queue" "raw_events" {
  name                      = "stock-raw-events"
  message_retention_seconds = 345600 # 4 days

  # AWS asks for at least 6x the Lambda timeout
  visibility_timeout_seconds = var.lambda_timeout * 6

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.raw_events_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Project = "StockDataPipeline"
    Layer   = "Raw"
  }
}

# Let the Raw bucket send messages to the queue
resource "aws_sqs_queue_policy" "raw_events" {
  queue_url = aws_sqs_queue.raw_events.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "s3.amazonaws.com"
      }

      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.raw_events.arn

      Condition = {
        ArnEquals = {
          "aws:SourceArn" = var.raw_bucket_arn
        }
      }
    }]
  })
}

# ==========================================
# Raw bucket -> SQS (only .parquet files under the raw prefix)
# ==========================================

resource "aws_s3_bucket_notification" "raw_to_sqs" {
  bucket = var.raw_bucket_name

  queue {
    queue_arn     = aws_sqs_queue.raw_events.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = var.raw_prefix
    filter_suffix = ".parquet"
  }

  # S3 sends a test message on create; the queue policy must exist first
  depends_on = [aws_sqs_queue_policy.raw_events]
}
