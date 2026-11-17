variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Pinggy tunnel address (source repo: `make tunnel`). Changes on every tunnel start:
#   export TF_VAR_source_host=xxxx.a.free.pinggy.link
#   export TF_VAR_source_port=12345
variable "source_host" {
  description = "Pinggy hostname that forwards to the local tutoring Postgres"
  type        = string
}

variable "source_port" {
  description = "Pinggy port that forwards to the local tutoring Postgres"
  type        = number
}

# No default. Set it before running (POSTGRES_PASSWORD from the source .env):
#   export TF_VAR_database_password=...
variable "database_password" {
  description = "PostgreSQL password for DMS"
  type        = string
  sensitive   = true
}
