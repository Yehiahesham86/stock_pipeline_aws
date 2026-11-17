variable "aws_region" {
  description = "AWS region for the DMS resources"
  type        = string
  default     = "us-east-1"
}

variable "replication_instance_class" {
  description = "DMS replication instance size"
  type        = string
  default     = "dms.t3.micro"
}

variable "allocated_storage" {
  description = "DMS replication instance storage in GB"
  type        = number
  default     = 5
}


# No defaults: the Pinggy address changes every time the tunnel starts
variable "source_host" {
  description = "PostgreSQL hostname exposed through Pinggy (from the root module)"
  type        = string
}

variable "source_port" {
  description = "PostgreSQL port exposed through Pinggy (from the root module)"
  type        = number
}

variable "database_name" {
  description = "PostgreSQL database name (POSTGRES_DB in source .env)"
  type        = string
  default     = "tutoring"
}

variable "database_username" {
  description = "PostgreSQL username (POSTGRES_USER in source .env)"
  type        = string
  default     = "tutoring_admin"
}

variable "source_schema" {
  description = "PostgreSQL schema DMS replicates (all tables in it)"
  type        = string
  default     = "app"
}

# No default: never a secret in code
variable "database_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}
# ---------- inputs wired from the root module ----------

variable "vpc_id" {
  description = "VPC ID from module.vpc_config"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs from module.vpc_config"
  type        = list(string)
}




variable "raw_prefix" {
  description = "Raw prefix from module.s3_raw"
  type        = string
}

variable "raw_bucket_name" {
  description = "raw bucket name from module.s3_raw"
  type        = string
}

variable "raw_bucket_arn" {
  description = "raw bucket ARN from module.s3_raw"
  type        = string
}