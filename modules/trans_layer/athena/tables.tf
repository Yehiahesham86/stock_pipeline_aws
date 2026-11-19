# ==========================================
# Tutoring tables: Bronze Iceberg DDL, one per table.
# Raw tables are NOT created here: catalog_manager owns them (reads the real
# schema of the newest DMS parquet file).
# Columns copied from source-stock-data-pipeline/sql/01_schema.sql.
#
# Types = what DMS writes to parquet (checked with pyarrow 2026-11-17):
#   BIGINT -> bigint, SMALLINT -> smallint, NUMERIC(p,s) -> decimal(p,s),
#   TIMESTAMPTZ -> timestamp (UTC), TEXT / CHAR(n) -> string
# Bronze: smallint -> int (Iceberg has no smallint).
#
# CREATE ... IF NOT EXISTS: editing a column here does NOT alter an existing
# table. New source columns are added at runtime by the trigger Lambda
# (ALTER TABLE ADD COLUMNS); this list is only the starting schema.
# ==========================================

locals {
  # [name, raw type]; list (not map) so the column order stays as in Postgres
  tables = {
    teachers = [
      ["teacher_id", "bigint"],
      ["full_name", "string"],
      ["email", "string"],
      ["country", "string"],
      ["hourly_rate", "decimal(8,2)"],
      ["status", "string"],
      ["created_at", "timestamp"],
      ["updated_at", "timestamp"],
    ]
    students = [
      ["student_id", "bigint"],
      ["full_name", "string"],
      ["email", "string"],
      ["country", "string"],
      ["plan", "string"],
      ["status", "string"],
      ["referred_by", "bigint"],
      ["created_at", "timestamp"],
      ["updated_at", "timestamp"],
    ]
    class_bookings = [
      ["booking_id", "bigint"],
      ["student_id", "bigint"],
      ["teacher_id", "bigint"],
      ["scheduled_at", "timestamp"],
      ["duration_min", "smallint"],
      ["status", "string"],
      ["cancel_reason", "string"],
      ["created_at", "timestamp"],
      ["updated_at", "timestamp"],
    ]
    payments = [
      ["payment_id", "bigint"],
      ["student_id", "bigint"],
      ["payment_type", "string"],
      ["plan", "string"],
      ["amount", "decimal(10,2)"],
      ["currency", "string"],
      ["refund_of", "bigint"],
      ["created_at", "timestamp"],
      ["updated_at", "timestamp"],
    ]
    referrals = [
      ["referral_id", "bigint"],
      ["referrer_id", "bigint"],
      ["referee_email", "string"],
      ["referee_id", "bigint"],
      ["status", "string"],
      ["created_at", "timestamp"],
      ["updated_at", "timestamp"],
    ]
  }

  bronze_ddl = [
    for table, columns in local.tables :
    templatefile("${path.module}/sql/create_bronze_table.sql", {
      bronze_database = var.bronze_database_name
      table           = table
      columns         = join(",\n", [for c in columns : "    ${c[0]} ${c[1] == "smallint" ? "int" : c[1]}"])
      bronze_location = "s3://${var.bronze_bucket_name}/${var.bronze_iceberg_prefix}${table}/"
    })
  ]
}
