terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Define variables for the crawler bucket name and AWS region
provider "aws" {
  region = var.aws_region
}

# ==========================================
# Bronze Database
# ==========================================

resource "aws_glue_catalog_database" "bronze" {
  name = var.database_name
}

# ==========================================
# Silver Database
# ==========================================

resource "aws_glue_catalog_database" "silver" {
  name = "stock_silver"
}

# ==========================================
# Gold Database
# ==========================================

resource "aws_glue_catalog_database" "gold" {
  name = "stock_gold"
}