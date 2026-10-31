variable "aws_region" {
  description = "AWS region for the DMS resources"
  type        = string
  default     = "us-east-1"
}

variable "replication_instance_class" {
  description = "DMS replication instance size"
  type        = string
  default     = "dms.t3.small"
}

variable "allocated_storage" {
  description = "DMS replication instance storage in GB"
  type        = number
  default     = 5
}


variable "source_host" {
  description = "PostgreSQL hostname exposed through Pinggy"
  type        = string
  default     = "ecpgw-217-53-215-119.run.pinggy-free.link"
}

variable "source_port" {
  description = "PostgreSQL port exposed through Pinggy"
  type        = number
  default     = 37595
}

variable "database_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "stock_market"
}

variable "database_username" {
  description = "PostgreSQL username"
  type        = string
  default     = "admin"
}

variable "database_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}