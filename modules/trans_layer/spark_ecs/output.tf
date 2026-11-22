# ---------- everything Step Functions needs for ecs:runTask ----------
output "cluster_arn" {
  value = aws_ecs_cluster.spark.arn
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.spark_job.arn
}

# for IAM: any revision of this task family
output "task_definition_family_arn" {
  value = aws_ecs_task_definition.spark_job.arn_without_revision
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "security_group_id" {
  value = aws_security_group.spark_job.id
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.spark_job.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.spark_job.repository_url
}
