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

resource "aws_glue_catalog_database" "bronze" {
  name = var.database_name
}