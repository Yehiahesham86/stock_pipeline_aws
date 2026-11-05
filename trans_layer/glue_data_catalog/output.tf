output "bronze_database_name" {
  value = aws_glue_catalog_database.bronze.name
}

output "bronze_database_arn" {
  value = aws_glue_catalog_database.bronze.arn
}

output "silver_database_name" {
  value = aws_glue_catalog_database.silver.name
}

output "silver_database_arn" {
  value = aws_glue_catalog_database.silver.arn
}
