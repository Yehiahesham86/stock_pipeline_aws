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
}

# ---------- Raw .parquet created -> SQS -> Lambda -> Athena (Raw -> Bronze) ----------
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
