# CloudWatch logging
# Log group owned by Terraform (else Lambda creates it on first run and it
# survives terraform destroy)
resource "aws_cloudwatch_log_group" "catalog_manager" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 7
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role = aws_iam_role.lambda_role.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}