output "lambda_role_arn" {
  value = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  value = aws_iam_role.lambda_role.name
}
output "ecr_repository_url" {
  value = aws_ecr_repository.lambda.repository_url
}

output "ecr_repository_arn" {
  value = aws_ecr_repository.lambda.arn
}
output "lambda_function_name" {
  value = aws_lambda_function.catalog_manager.function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.catalog_manager.arn
}