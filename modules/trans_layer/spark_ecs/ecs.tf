# ==========================================
# Bronze -> Silver Spark job on ECS Fargate (one container, Spark local mode).
#
# Why not EMR Serverless: account quota "max concurrent vCPUs" = 0 (2026-11-22).
#
# Cost (no free tier for Fargate): billed per second while the task runs,
# 1 vCPU + 3 GB ~ $0.054/hour -> a 5-minute run ~ $0.005. Nothing runs between
# runs: Step Functions starts the task, the task exits when the job ends.
# No NAT: the task gets a public IP in a public subnet (to pull from ECR and
# reach S3 / Glue) and accepts no inbound traffic.
# ==========================================

resource "aws_ecs_cluster" "spark" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_cloudwatch_log_group" "spark_job" {
  name              = "/ecs/${var.name}"
  retention_in_days = 7
}

# no inbound rules; outbound HTTPS to ECR / S3 / Glue / CloudWatch Logs
resource "aws_security_group" "spark_job" {
  name                   = "${var.name}-task"
  description            = "Spark job task: no inbound, outbound only"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_task_definition" "spark_job" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  # smallest Fargate size that runs Spark + Python workers: 1 vCPU / 3 GB
  cpu    = var.task_cpu
  memory = var.task_memory

  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "spark"
    image     = "${aws_ecr_repository.spark_job.repository_url}@${docker_registry_image.spark_job.sha256_digest}"
    essential = true

    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      { name = "AWS_DEFAULT_REGION", value = var.aws_region },
    ]

    # ENTRYPOINT is spark-submit; this is everything after it
    command = concat(
      [
        "--master", "local[*]",
        "--driver-memory", var.driver_memory,
        # Iceberg tables in the Glue Data Catalog, files through S3FileIO
        "--conf", "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
        "--conf", "spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog",
        "--conf", "spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog",
        "--conf", "spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO",
        "--conf", "spark.sql.catalog.glue_catalog.warehouse=s3://${var.silver_bucket_name}/iceberg/",
        # plain s3:// (quarantine parquet) through S3A, credentials from the task role
        "--conf", "spark.hadoop.fs.s3.impl=org.apache.hadoop.fs.s3a.S3AFileSystem",
        "--conf", "spark.hadoop.fs.s3a.aws.credentials.provider=com.amazonaws.auth.DefaultAWSCredentialsProviderChain",
        # tiny CDC batches on 1 core
        "--conf", "spark.sql.shuffle.partitions=4",
        "--conf", "spark.ui.enabled=false",
        "/app/bronze_to_silver.py",
      ],
      [
        "--bronze-db", var.bronze_database_name,
        "--silver-db", var.silver_database_name,
        "--quarantine-bucket", var.quarantine_bucket_name,
        "--tables", join(",", var.table_names),
      ]
    )

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.spark_job.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "bronze-to-silver"
      }
    }
  }])
}
