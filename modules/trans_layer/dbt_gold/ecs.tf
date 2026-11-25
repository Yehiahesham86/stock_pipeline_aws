# ==========================================
# Silver -> Gold: `dbt build` as an ECS Fargate task on the Spark cluster.
#
# dbt only sends SQL to Athena and waits; the work happens in Athena. So the
# task is the smallest Fargate size (0.25 vCPU / 0.5 GB, ~$0.012/hour -> a
# 2-minute run ~ $0.0004). Athena bills $5 per TB scanned: Gold reads a few MB.
#
# Why not Lambda: dbt writes target/ + logs/ to disk, uses threads, and a
# long build could pass the 15-minute cap. Fargate runs it like a laptop does.
# ==========================================

resource "aws_cloudwatch_log_group" "dbt" {
  name              = "/ecs/${var.name}"
  retention_in_days = 7
}

# no inbound rules; outbound HTTPS to ECR / Athena / Glue / S3 / CloudWatch Logs
resource "aws_security_group" "dbt" {
  name                   = "${var.name}-task"
  description            = "dbt task: no inbound, outbound only"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_task_definition" "dbt" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = var.task_cpu
  memory = var.task_memory

  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "dbt"
    image     = "${aws_ecr_repository.dbt.repository_url}@${docker_registry_image.dbt.sha256_digest}"
    essential = true

    # read by dbt/profiles.yml + dbt/models/sources.yml through env_var()
    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      { name = "AWS_DEFAULT_REGION", value = var.aws_region },
      { name = "ATHENA_WORKGROUP", value = var.athena_workgroup_name },
      { name = "ATHENA_RESULTS_LOCATION", value = var.athena_results_location },
      { name = "GOLD_DATA_DIR", value = "s3://${var.gold_bucket_name}/iceberg/" },
      { name = "GOLD_SCHEMA", value = var.gold_database_name },
      { name = "SILVER_SCHEMA", value = var.silver_database_name },
      { name = "BRONZE_SCHEMA", value = var.bronze_database_name },
      { name = "DBT_THREADS", value = tostring(var.dbt_threads) },
    ]

    # ENTRYPOINT is dbt; models + tests in one command, a failing test = exit code 1
    command = ["build", "--target", "aws"]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.dbt.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "silver-to-gold"
      }
    }
  }])
}
