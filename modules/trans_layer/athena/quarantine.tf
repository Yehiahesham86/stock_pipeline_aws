# ==========================================
# Quarantine tables: one Glue table per tutoring table over the bad rows the
# Spark job writes (spark_ecs/jobs/bronze_to_silver.py):
#
#   s3://<quarantine bucket>/<table>/window=<start>_<end>/part-*.parquet
#
# Not partitioned: Athena reads every file under the table folder, including
# each window=... subfolder, and skips _SUCCESS. New runs show up with no
# MSCK REPAIR / crawler. The window is in "$path" if you need it.
#
# Parquet is read by column NAME: a column the files don't have = NULL, a new
# source column not listed here is just not shown (add it here to see it).
#
#   SELECT student_id, email, dq_errors, quarantined_at
#   FROM stock_quarantine.students ORDER BY quarantined_at DESC;
# ==========================================

resource "aws_glue_catalog_table" "quarantine" {
  for_each = local.tables

  database_name = var.quarantine_database_name
  name          = each.key
  table_type    = "EXTERNAL_TABLE"
  description   = "Bad ${each.key} rows from the Bronze -> Silver DQ checks"

  parameters = {
    EXTERNAL       = "TRUE"
    classification = "parquet"
  }

  storage_descriptor {
    location      = "s3://${var.quarantine_bucket_name}/${each.key}/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "dms_ts"
      type = "string"
    }

    # source columns; smallint -> int like Bronze (Spark reads Bronze as int)
    dynamic "columns" {
      for_each = each.value
      content {
        name = columns.value[0]
        type = columns.value[1] == "smallint" ? "int" : columns.value[1]
      }
    }

    # DMS + Bronze + DQ columns, as written by the Spark job
    dynamic "columns" {
      for_each = [
        ["dms_change_seq", "string", "DMS change order inside one commit"],
        ["source_file", "string", "Raw file this event came from"],
        ["op", "string", "I / U / D"],
        ["dq_errors", "array<string>", "names of the DQ rules this row failed"],
        ["run_id", "string", "Spark run that quarantined it"],
        ["quarantined_at", "timestamp", "when it was quarantined (UTC)"],
      ]
      content {
        name    = columns.value[0]
        type    = columns.value[1]
        comment = columns.value[2]
      }
    }
  }
}
