
variable "bronze_bucket_name" {
  type        = string
  description = "Bronze S3 bucket name"
}

variable "athena_results_prefix" {
  type        = string
  description = "S3 prefix for Athena query execution results"
  default     = "athena-results/"
}
