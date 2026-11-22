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
  description = "Spark task is stopped after this (cost cap)"
  type        = number
  default     = 30
}

# ---------- Stage 1 (from module.s3_athena_trigger) ----------
variable "raw_to_bronze_function_arn" {
  type = string
}

# ---------- Stage 2 (from module.spark_ecs + module.vpc_config) ----------
variable "ecs_cluster_arn" {
  type = string
}

variable "ecs_task_definition_arn" {
  type = string
}

variable "ecs_task_definition_family_arn" {
  type = string
}

variable "ecs_task_role_arn" {
  type = string
}

variable "ecs_execution_role_arn" {
  type = string
}

variable "ecs_security_group_id" {
  type = string
}

variable "ecs_subnet_ids" {
  description = "Public subnets (task gets a public IP, no NAT)"
  type        = list(string)
}
