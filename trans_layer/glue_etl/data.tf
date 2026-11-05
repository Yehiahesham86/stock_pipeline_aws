data "terraform_remote_state" "s3_bronze" {
  backend = "local"

  config = {
    path = "../../storage/s3_bronze/terraform.tfstate"
  }
}

data "terraform_remote_state" "s3_silver" {
  backend = "local"

  config = {
    path = "../../storage/s3_silver/terraform.tfstate"
  }
}

data "terraform_remote_state" "glue_catalog" {
  backend = "local"

  config = {
    path = "../glue_data_catalog/terraform.tfstate"
  }
}
