variable "raw_prefix" {
  type        = string
  description = "Raw S3 prefix monitored by EventBridge"
}
variable "raw_bucket_name" {
  type = string
}

variable "raw_bucket_arn" {
  type = string
}