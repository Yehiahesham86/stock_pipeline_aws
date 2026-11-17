-- Raw: external table over the DMS parquet files (rendered by templatefile).
-- Athena reads parquet columns by NAME. Baseline only: catalog_manager
-- later overwrites this table with the real schema of a DMS file.
--   op             I / U / D   (DMS endpoint include_op_for_full_load)
--   dms_ts         commit time (DMS endpoint timestamp_column_name)
--   dms_change_seq order inside a commit (DMS task add-column rule)
-- DMS writes into date folders (YYYY/MM/DD); Athena reads sub-folders too.
CREATE EXTERNAL TABLE IF NOT EXISTS ${raw_database}.${table} (
    op              string,
    dms_ts          string,
    ticker          string,
    price_date      date,
    open            double,
    high            double,
    low             double,
    close           double,
    volume          bigint,
    dms_change_seq  string
)
STORED AS PARQUET
LOCATION '${raw_location}'
