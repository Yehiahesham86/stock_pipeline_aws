# ---------- everything Step Functions needs for ecs:runTask ----------
output "task_definition_arn" {
  value = aws_ecs_task_definition.dbt.arn
}

# for IAM: any revision of this task family
output "task_definition_family_arn" {
  value = aws_ecs_task_definition.dbt.arn_without_revision
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "security_group_id" {
  value = aws_security_group.dbt.id
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.dbt.name
}
