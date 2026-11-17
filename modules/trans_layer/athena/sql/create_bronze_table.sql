-- Bronze: Iceberg table (rendered by templatefile).
-- Same column names as Raw, plus the two the trigger Lambda adds:
--   INSERT INTO bronze (cols, source_file, ingested_at) SELECT cols, path, now FROM raw
CREATE TABLE IF NOT EXISTS ${bronze_database}.${table} (
    op              string,
    dms_ts          string,
    ticker          string,
    price_date      date,
    open            double,
    high            double,
    low             double,
    close           double,
    volume          bigint,
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
