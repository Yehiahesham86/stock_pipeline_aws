variable "quarantine_bucket_name" {
  description = "Bucket for rows that failed data quality"
  type        = string
  default     = "tutoring-quarantine-yh-toutoring-1345"
}

variable "quarantine_retention_days" {
  description = "Days before a quarantined file is deleted"
  type        = number
  default     = 30
}
