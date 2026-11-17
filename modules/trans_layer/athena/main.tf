
resource "aws_athena_workgroup" "stock_pipeline" {
  name        = "stock-pipeline-workgroup"
  description = "Athena workgroup for the stock data lake"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    result_configuration {
      output_location = "s3://${var.bronze_bucket_name}/${var.athena_results_prefix}"
    }
  }

  tags = {
    Project = "StockDataPipeline"
    Layer   = "Analytics"
  }
}
