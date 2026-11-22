# ==========================================
# EMR Serverless Spark application for Bronze -> Silver.
#
# Cost rules (no free tier for EMR Serverless; billed per vCPU-hour + GB-hour
# only while a job runs):
#   - NO initial_capacity  -> nothing pre-warmed, nothing billed while idle
#   - auto_stop after 1 idle minute
#   - maximum_capacity caps a runaway job: driver 1 vCPU + 1 executor 1 vCPU
#   - ARM64 (Graviton) is ~20% cheaper than X86_64
#   - no network_configuration -> no VPC, no NAT; S3 + Glue reached through
#     the AWS service endpoints
# Smallest worker EMR Serverless allows = 1 vCPU / 2 GB; Spark sizes are set
# per job run (spark.driver.cores=1, spark.executor.cores=1, ...).
# ==========================================

resource "aws_emrserverless_application" "spark" {
  name          = var.application_name
  release_label = var.release_label
  type          = "spark"
  architecture  = "ARM64"

  maximum_capacity {
    cpu    = var.max_cpu
    memory = var.max_memory
  }

  auto_start_configuration {
    enabled = true
  }

  auto_stop_configuration {
    enabled              = true
    idle_timeout_minutes = 1
  }

  tags = {
    Project = "TutoringPipeline"
    Layer   = "Silver"
  }
}
