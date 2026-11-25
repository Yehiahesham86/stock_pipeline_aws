# =============================================================
# ROOT: calls every folder in modules/ and connects them.
#
# BEFORE: you ran `terraform apply` in 7 folders, in order,
#         and folders read each other's .tfstate files.
# AFTER:  one `terraform apply` here.
#         module.<name>.<output> passes values between modules.
#
# How to read a module block:
#   source = which folder
#   x = y  -> x is a variable in that folder, y is the value we give it
# =============================================================

# ---------- was vpc_config/ ----------
module "vpc_config" {
  source = "./modules/vpc_config"
}

# ---------- was storage/s3_raw/ ----------
module "s3_raw" {
  source = "./modules/storage/s3_raw"
}


# ---------- was storage/s3_bronze/ ----------
module "s3_bronze" {
  source = "./modules/storage/s3_bronze"
}

# ---------- was storage/s3_silver/ ----------
module "s3_silver" {
  source = "./modules/storage/s3_silver"
}

# ---------- the 4 business tables built by dbt ----------
module "s3_gold" {
  source = "./modules/storage/s3_gold"
}

# ---------- bad rows from the Bronze -> Silver data quality check ----------
module "s3_quarantine" {
  source = "./modules/storage/s3_quarantine"
}

# ---------- was trans_layer/glue_data_catalog/ ----------
module "glue_data_catalog" {
  source = "./modules/trans_layer/glue_data_catalog"
}

# ---------- was ingestion/dms/ ----------
module "dms" {
  source = "./modules/ingestion/dms"

  # BEFORE: data.terraform_remote_state.vpc.outputs.vpc_id
  vpc_id            = module.vpc_config.vpc_id
  public_subnet_ids = module.vpc_config.public_subnet_ids

  # BEFORE: data.terraform_remote_state.s3.outputs.bronze_...
  raw_bucket_name = module.s3_raw.raw_bucket_name
  raw_bucket_arn  = module.s3_raw.raw_bucket_arn
  raw_prefix      = module.s3_raw.raw_prefix

  # local tutoring Postgres, reached through the Pinggy tunnel
  source_host       = var.source_host
  source_port       = var.source_port
  database_password = var.database_password
}



# ---------- was trans_layer/lambda_trans/ ----------
module "lambda_trans" {
  source = "./modules/trans_layer/lambda_trans"

  # owns the Raw tables: schema from a real DMS parquet file (instead of a crawler)
  aws_region        = var.aws_region
  raw_bucket_name   = module.s3_raw.raw_bucket_name
  raw_bucket_arn    = module.s3_raw.raw_bucket_arn
  raw_prefix        = module.s3_raw.raw_prefix
  source_schema     = module.athena.source_schema
  raw_database_name = module.glue_data_catalog.raw_database_name
  table_names       = module.athena.table_names
}


module "athena" {
  source = "./modules/trans_layer/athena"

  bronze_bucket_name = module.s3_bronze.bronze_bucket_name

  # for the Bronze table DDL in sql/ (Raw tables: catalog_manager)
  bronze_database_name = module.glue_data_catalog.bronze_database_name

  # Glue tables over the Spark job's bad rows (quarantine.tf)
  quarantine_database_name = module.glue_data_catalog.quarantine_database_name
  quarantine_bucket_name   = module.s3_quarantine.quarantine_bucket_name
}

# ---------- Raw .parquet created -> SQS (drained by the pipeline_run state machine) -> Lambda -> Athena (Raw -> Bronze) ----------
module "s3_athena_trigger" {
  source = "./modules/ingestion/s3_athena_trigger"

  aws_region = var.aws_region

  raw_bucket_name = module.s3_raw.raw_bucket_name
  raw_bucket_arn  = module.s3_raw.raw_bucket_arn
  raw_prefix      = module.s3_raw.raw_prefix

  bronze_bucket_arn = module.s3_bronze.bronze_bucket_arn

  athena_workgroup_name = module.athena.athena_workgroup_name
  athena_workgroup_arn  = module.athena.athena_workgroup_arn

  raw_database_name    = module.glue_data_catalog.raw_database_name
  bronze_database_name = module.glue_data_catalog.bronze_database_name

  # Bronze tables are created through Athena on apply
  table_names      = module.athena.table_names
  source_schema    = module.athena.source_schema
  bronze_table_ddl = module.athena.bronze_table_ddl

  # called per file to create / update the Raw table first
  catalog_manager_function_name = module.lambda_trans.lambda_function_name
  catalog_manager_function_arn  = module.lambda_trans.lambda_function_arn
}

# ---------- Bronze Iceberg -> Spark on ECS Fargate -> Silver Iceberg / quarantine ----------
module "spark_ecs" {
  source = "./modules/trans_layer/spark_ecs"

  aws_region = var.aws_region
  vpc_id     = module.vpc_config.vpc_id

  bronze_bucket_arn     = module.s3_bronze.bronze_bucket_arn
  silver_bucket_arn     = module.s3_silver.silver_bucket_arn
  quarantine_bucket_arn = module.s3_quarantine.quarantine_bucket_arn

  bronze_database_name = module.glue_data_catalog.bronze_database_name
  silver_database_name = module.glue_data_catalog.silver_database_name

  # job arguments + Silver warehouse location
  silver_bucket_name     = module.s3_silver.silver_bucket_name
  quarantine_bucket_name = module.s3_quarantine.quarantine_bucket_name
  table_names            = module.athena.table_names
}

# ---------- Silver Iceberg -> dbt build on ECS Fargate (SQL runs in Athena) -> Gold Iceberg ----------
module "dbt_gold" {
  source = "./modules/trans_layer/dbt_gold"

  aws_region = var.aws_region
  vpc_id     = module.vpc_config.vpc_id

  athena_workgroup_name   = module.athena.athena_workgroup_name
  athena_workgroup_arn    = module.athena.athena_workgroup_arn
  athena_results_location = module.athena.athena_results_location
  athena_results_prefix   = module.athena.athena_results_prefix

  bronze_bucket_arn = module.s3_bronze.bronze_bucket_arn
  silver_bucket_arn = module.s3_silver.silver_bucket_arn
  gold_bucket_arn   = module.s3_gold.gold_bucket_arn
  gold_bucket_name  = module.s3_gold.gold_bucket_name

  # Bronze only for class_bookings delete events (hard-deleted cancellations)
  bronze_database_name = module.glue_data_catalog.bronze_database_name
  silver_database_name = module.glue_data_catalog.silver_database_name
  gold_database_name   = module.glue_data_catalog.gold_database_name
}

# ---------- one scheduled run: Raw -> Bronze (Lambda) -> Silver (Spark on ECS) -> Gold (dbt on ECS) ----------
module "pipeline_run" {
  source = "./modules/orchestration/pipeline_run"

  aws_region = var.aws_region

  # stage 1: trigger Lambda in drain mode
  raw_to_bronze_function_arn = module.s3_athena_trigger.athena_trigger_function_arn

  # stage 2: Spark task on Fargate in the public subnets
  ecs_cluster_arn                = module.spark_ecs.cluster_arn
  ecs_task_definition_arn        = module.spark_ecs.task_definition_arn
  ecs_task_definition_family_arn = module.spark_ecs.task_definition_family_arn
  ecs_task_role_arn              = module.spark_ecs.task_role_arn
  ecs_execution_role_arn         = module.spark_ecs.execution_role_arn
  ecs_security_group_id          = module.spark_ecs.security_group_id
  ecs_subnet_ids                 = module.vpc_config.public_subnet_ids

  # stage 3: dbt task on the same cluster + subnets
  dbt_task_definition_arn        = module.dbt_gold.task_definition_arn
  dbt_task_definition_family_arn = module.dbt_gold.task_definition_family_arn
  dbt_task_role_arn              = module.dbt_gold.task_role_arn
  dbt_execution_role_arn         = module.dbt_gold.execution_role_arn
  dbt_security_group_id          = module.dbt_gold.security_group_id
}
