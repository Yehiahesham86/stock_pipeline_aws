output "crawler_name" {
  value = aws_glue_crawler.bronze.name
}

output "crawler_role_arn" {
  value = aws_iam_role.crawler_role.arn
}