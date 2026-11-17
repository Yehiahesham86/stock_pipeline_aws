
resource "aws_sqs_queue" "ingestion_dlq" {
  name                      = "stock-ingestion-dlq"
  message_retention_seconds = 1209600

  tags = {
    Project = "StockDataPipeline"
    Layer   = "Ingestion"
  }
}

resource "aws_sqs_queue" "ingestion" {
  name                       = "stock-ingestion-queue"
  visibility_timeout_seconds = 180
  message_retention_seconds  = 345600

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.ingestion_dlq.arn
    maxReceiveCount     = 5
  })

  tags = {
    Project = "StockDataPipeline"
    Layer   = "Ingestion"
  }
}
