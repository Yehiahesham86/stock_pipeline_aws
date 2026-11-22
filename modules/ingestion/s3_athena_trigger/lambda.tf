# ==========================================
# Lambda: queue message -> catalog_manager (Raw table) -> Athena INSERT INTO Bronze
# Step Functions invokes it ({"drain": true}); it pulls messages and calls catalog_manager itself.
# ==========================================

data "archive_file" "athena_trigger" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_package.zip"
}

resource "aws_cloudwatch_log_group" "athena_trigger" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "athena_trigger" {
  function_name = var.function_name
  role          = aws_iam_role.athena_trigger.arn

  runtime = "python3.12"
  handler = "lambda_function.lambda_handler"

  filename         = data.archive_file.athena_trigger.output_path
  source_code_hash = data.archive_file.athena_trigger.output_base64sha256

  timeout     = var.lambda_timeout
  memory_size = 128

  environment {
    variables = {
      ATHENA_WORKGROUP         = var.athena_workgroup_name
      RAW_DATABASE             = var.raw_database_name
      BRONZE_DATABASE          = var.bronze_database_name
      RAW_PREFIX               = var.raw_prefix
      SOURCE_SCHEMA            = var.source_schema
      TABLES                   = join(",", var.table_names)
      CATALOG_MANAGER_FUNCTION = var.catalog_manager_function_name
      QUEUE_URL                = aws_sqs_queue.raw_events.url
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.logs,
    aws_cloudwatch_log_group.athena_trigger
  ]
}

# ==========================================
# Create the Bronze (Iceberg) tables through Athena, on apply.
# Same Lambda, called with {"ddl": [...]} instead of an SQS event.
# Runs again only when the SQL changes (CREATE ... IF NOT EXISTS).
# Raw tables are NOT made here: catalog_manager creates them per file.
# ==========================================

resource "aws_lambda_invocation" "create_tables" {
  function_name = aws_lambda_function.athena_trigger.function_name

  input = jsonencode({
    ddl = var.bronze_table_ddl
  })

  depends_on = [
    aws_iam_role_policy.athena,
    aws_iam_role_policy.glue,
    aws_iam_role_policy.s3
  ]
}

# No SQS -> Lambda event source mapping: Step Functions (module pipeline_run)
# invokes this Lambda with {"drain": true} and it pulls from the queue itself.
