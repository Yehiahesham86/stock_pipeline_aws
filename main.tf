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
  bronze_bucket_name = module.s3_bronze.bronze_bucket_name
  bronze_bucket_arn  = module.s3_bronze.bronze_bucket_arn
  bronze_prefix      = module.s3_bronze.bronze_prefix

  database_password = var.database_password
}

# ---------- was trans_layer/crawler/ ----------
module "crawler" {
  source = "./modules/trans_layer/crawler"

  bronze_bucket_name   = module.s3_bronze.bronze_bucket_name
  bronze_bucket_arn    = module.s3_bronze.bronze_bucket_arn
  bronze_prefix        = module.s3_bronze.bronze_prefix
  bronze_database_name = module.glue_data_catalog.bronze_database_name
}

# ---------- was trans_layer/glue_etl/ ----------
module "glue_etl" {
  source = "./modules/trans_layer/glue_etl"

  bronze_bucket_arn    = module.s3_bronze.bronze_bucket_arn
  silver_bucket_name   = module.s3_silver.silver_bucket_name
  silver_bucket_arn    = module.s3_silver.silver_bucket_arn
  bronze_database_name = module.glue_data_catalog.bronze_database_name
  silver_database_name = module.glue_data_catalog.silver_database_name
}

# ---------- was trans_layer/lambda_trans/ ----------
module "lambda_trans" {
  source = "./modules/trans_layer/lambda_trans"

  aws_region           = var.aws_region
  bronze_bucket_name   = module.s3_bronze.bronze_bucket_name
  bronze_bucket_arn    = module.s3_bronze.bronze_bucket_arn
  bronze_prefix        = module.s3_bronze.bronze_prefix
  bronze_database_name = module.glue_data_catalog.bronze_database_name
}
