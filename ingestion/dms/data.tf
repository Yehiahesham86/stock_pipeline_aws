
variable "vpc_state_path" {
  description = "Path to the VPC Terraform state file"
  type        = string
  default     = "../../vpc_config/terraform.tfstate"
}

variable "s3_state_path" {
  description = "Path to the S3 Terraform state file"
  type        = string
  default     = "../../storage/s3_bronze/terraform.tfstate"
}

data "terraform_remote_state" "vpc" {
  backend = "local"

  config = {
    path = var.vpc_state_path
  }
}

data "terraform_remote_state" "s3" {
  backend = "local"

  config = {
    path = var.s3_state_path
  }
}
