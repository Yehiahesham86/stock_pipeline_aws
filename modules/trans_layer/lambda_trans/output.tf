output "lambda_role_arn" {
  value = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  value = aws_iam_role.lambda_role.name
}

output "lambda_function_name" {
  value = aws_lambda_function.catalog_manager.function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.catalog_manager.arn
}
output "ecr_repository_url" {
  value = aws_ecr_repository.catalog_manager.repository_url
}

output "ecr_repository_arn" {
  value = aws_ecr_repository.catalog_manager.arn
}