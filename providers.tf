

provider "aws" {
  region = "us-east-1"
}

provider "docker" {
  registry_auth {
    address  = trimprefix(data.aws_ecr_authorization_token.ecr.proxy_endpoint, "https://")
    username = data.aws_ecr_authorization_token.ecr.user_name
    password = data.aws_ecr_authorization_token.ecr.password
  }
}

data "aws_ecr_authorization_token" "ecr" {}
