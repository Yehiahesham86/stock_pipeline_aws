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
