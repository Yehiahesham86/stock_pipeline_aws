output "application_id" {
  value = aws_emrserverless_application.spark.id
}

output "job_role_arn" {
  value = aws_iam_role.emr_job.arn
}

output "artifacts_bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}

# ---------- everything `aws emr-serverless start-job-run` needs ----------
output "entry_point" {
  value = "s3://${aws_s3_bucket.artifacts.bucket}/${aws_s3_object.job_entry_point.key}"
}

output "entry_point_arguments" {
  value = [
    "--bronze-db", var.bronze_database_name,
    "--silver-db", var.silver_database_name,
    "--quarantine-bucket", var.quarantine_bucket_name,
    "--tables", join(",", var.table_names),
  ]
}

# Smallest sizing: driver 1 vCPU + 1 executor 1 vCPU (2 GB heap each), no dynamic allocation.
# Iceberg: jar bundled in EMR 7, catalog "glue_catalog" = AWS Glue Data Catalog.
output "spark_submit_parameters" {
  value = join(" ", [
    "--py-files s3://${aws_s3_bucket.artifacts.bucket}/${aws_s3_object.job_transforms.key}",
    "--conf spark.jars=/usr/share/aws/iceberg/lib/iceberg-spark3-runtime.jar",
    "--conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
    "--conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog",
    "--conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog",
    "--conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO",
    "--conf spark.sql.catalog.glue_catalog.warehouse=s3://${var.silver_bucket_name}/iceberg/",
    "--conf spark.driver.cores=1 --conf spark.driver.memory=2g",
    "--conf spark.executor.cores=1 --conf spark.executor.memory=2g",
    "--conf spark.executor.instances=1 --conf spark.dynamicAllocation.enabled=false",
  ])
}

output "log_uri" {
  value = "s3://${aws_s3_bucket.artifacts.bucket}/logs/"
}

output "application_arn" {
  value = aws_emrserverless_application.spark.arn
}
