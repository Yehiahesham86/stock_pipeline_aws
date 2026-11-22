variable "aws_region" {
  type = string
}

variable "state_machine_name" {
  type    = string
  default = "tutoring-pipeline-run"
}

# hourly: CDC files from DMS are small; a run with no new Raw files costs ~$0
variable "schedule_expression" {
  description = "EventBridge Scheduler expression"
  type        = string
  default     = "rate(1 hour)"
}

variable "schedule_enabled" {
  description = "false = state machine only runs when started by hand"
  type        = bool
  default     = true
}

variable "max_drain_loops" {
  description = "Max trigger-Lambda calls per run (each stops early when time runs short)"
  type        = number
  default     = 10
}

variable "job_timeout_minutes" {
  description = "EMR job is cancelled after this (cost cap)"
  type        = number
  default     = 30
}

# ---------- Stage 1 (from module.s3_athena_trigger) ----------
variable "raw_to_bronze_function_arn" {
  type = string
}

# ---------- Stage 2 (from module.emr_serverless) ----------
variable "emr_application_id" {
  type = string
}

variable "emr_application_arn" {
  type = string
}

variable "emr_job_role_arn" {
  type = string
}

variable "emr_entry_point" {
  type = string
}

variable "emr_entry_point_arguments" {
  type = list(string)
}

variable "emr_spark_submit_parameters" {
  type = string
}

variable "emr_log_uri" {
  type = string
}
