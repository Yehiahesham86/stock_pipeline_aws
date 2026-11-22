output "state_machine_arn" {
  value = aws_sfn_state_machine.pipeline.arn
}

output "schedule_name" {
  value = aws_scheduler_schedule.pipeline.name
}
