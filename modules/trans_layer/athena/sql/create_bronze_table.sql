-- Bronze: Iceberg table, one per source table (rendered by templatefile in tables.tf).
-- Append-only: every DMS change event is kept (MERGE happens in Silver).
--   op             I / U / D   (DMS endpoint include_op_for_full_load)
--   dms_ts         commit time (DMS endpoint timestamp_column_name)
--   dms_change_seq order inside a commit (DMS task add-column rule; empty on full load)
--   source_file    Raw parquet file the row came from (idempotency check)
--   ingested_at    when the trigger Lambda inserted it
CREATE TABLE IF NOT EXISTS ${bronze_database}.${table} (
    op              string,
    dms_ts          string,
${columns},
    dms_change_seq  string,
    source_file     string,
    ingested_at     timestamp
)
LOCATION '${bronze_location}'
TBLPROPERTIES (
    'table_type' = 'ICEBERG',
    'format' = 'parquet',
    'write_compression' = 'snappy'
)
