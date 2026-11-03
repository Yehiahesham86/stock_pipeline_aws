output "database_name" {
  value = aws_glue_catalog_database.bronze.name
}

output "database_arn" {
  value = aws_glue_catalog_database.bronze.arn
}