# BEFORE: every folder had its own provider "aws" block.
# AFTER:  one provider here. All modules use it automatically.
provider "aws" {
  region = var.aws_region
}
