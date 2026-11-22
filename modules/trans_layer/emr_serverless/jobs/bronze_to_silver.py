"""EMR Serverless job: Bronze Iceberg -> DQ -> Silver Iceberg (MERGE) / quarantine.

Thin wrapper: args, read, call transforms.py, write. Logic + rules live in
transforms.py (shipped with --py-files).

Per table:
  1. Bronze snapshot window: (last processed snapshot, current snapshot]
     read from the control table glue_catalog.<silver_db>.etl_control.
     Bronze is append-only, so an Iceberg incremental read returns exactly the
     rows appended in that window (no watermark on ingested_at: two Lambda
     INSERTs can commit out of order and a timestamp watermark would skip rows).
  2. latest event per key -> dq_errors -> good / bad
  3. good -> MERGE INTO glue_catalog.<silver_db>.<table> (created on first run)
     bad  -> s3://<quarantine>/<table>/window=<start>_<end>/  (overwrite)
  4. append a row to etl_control (only after 3 succeeded)

Idempotency: if the job dies between 3 and 4, the re-run reads the same
window again. MERGE only applies events at least as new as Silver's (no
change), and the quarantine path is keyed by the window + overwritten
(no duplicate bad rows).

Args:
  --bronze-db  --silver-db  --quarantine-bucket  --tables teachers,students,...
Spark conf (start-job-run): Iceberg extensions + catalog "glue_catalog" (GlueCatalog).
"""

import argparse
import sys
import uuid

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

import transforms as T

CATALOG = "glue_catalog"


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--bronze-db", required=True)
    p.add_argument("--silver-db", required=True)
    p.add_argument("--quarantine-bucket", required=True)
    p.add_argument("--tables", required=True, help="comma-separated, e.g. teachers,students")
    return p.parse_args()


def ensure_control_table(spark, silver_db):
    spark.sql(f"""
        CREATE TABLE IF NOT EXISTS {CATALOG}.{silver_db}.etl_control (
            table_name        string,
            start_snapshot_id bigint,
            end_snapshot_id   bigint,
            events_read       bigint,
            good_rows         bigint,
            bad_rows          bigint,
            run_id            string,
            processed_at      timestamp
        ) USING iceberg
    """)


def last_processed_snapshot(spark, silver_db, table):
    row = spark.sql(f"""
        SELECT end_snapshot_id FROM {CATALOG}.{silver_db}.etl_control
        WHERE table_name = '{table}'
        ORDER BY processed_at DESC LIMIT 1
    """).first()
    return row[0] if row else None


def current_snapshot(spark, bronze_table):
    row = spark.sql(f"""
        SELECT snapshot_id FROM {bronze_table}.snapshots
        ORDER BY committed_at DESC LIMIT 1
    """).first()
    return row[0] if row else None


def read_bronze_window(spark, bronze_table, start, end):
    reader = spark.read.format("iceberg")
    if start is None:
        # first run: everything up to and including `end`
        return reader.option("snapshot-id", end).load(bronze_table)
    # start exclusive, end inclusive; fails loudly if Bronze ever had a non-append snapshot
    return reader.option("start-snapshot-id", start).option("end-snapshot-id", end).load(bronze_table)


def ensure_silver_table(spark, silver_table, good_df):
    """Create Silver on the first run; add columns that appeared in Bronze later."""
    if not spark.catalog.tableExists(silver_table):
        good_df.limit(0).drop("op").writeTo(silver_table).using("iceberg").create()
        return
    existing = set(spark.table(silver_table).columns)
    for field in good_df.drop("op").schema.fields:
        if field.name not in existing:
            spark.sql(f"ALTER TABLE {silver_table} ADD COLUMNS ({field.name} {field.dataType.simpleString()})")


def process_table(spark, args, table, run_id):
    key = T.PRIMARY_KEYS[table]
    bronze_table = f"{CATALOG}.{args.bronze_db}.{table}"
    silver_table = f"{CATALOG}.{args.silver_db}.{table}"

    start = last_processed_snapshot(spark, args.silver_db, table)
    end = current_snapshot(spark, bronze_table)
    if end is None or end == start:
        print(f"[{table}] nothing new (snapshot {end})")
        return

    events = read_bronze_window(spark, bronze_table, start, end)
    keep = T.silver_columns(events.columns) + ["op"]
    latest = T.latest_event_per_key(events, key).select(*keep)
    checked = T.add_dq_errors(latest, table, key).cache()
    good, bad = T.split_valid(checked)

    events_read = events.count()
    good_rows = good.count()
    bad_rows = bad.count()

    if good_rows:
        ensure_silver_table(spark, silver_table, good)
        good.createOrReplaceTempView("batch")
        silver_cols = [c for c in good.columns if c != "op"]
        spark.sql(T.build_merge_sql(silver_table, "batch", key, silver_cols))

    if bad_rows:
        path = f"s3://{args.quarantine_bucket}/{table}/window={start or 0}_{end}/"
        (
            bad.withColumn("run_id", F.lit(run_id))
            .withColumn("quarantined_at", F.current_timestamp())
            .write.mode("overwrite")
            .parquet(path)
        )
        print(f"[{table}] {bad_rows} bad rows -> {path}")

    spark.createDataFrame(
        [(table, start, end, events_read, good_rows, bad_rows, run_id)],
        "table_name string, start_snapshot_id bigint, end_snapshot_id bigint, "
        "events_read bigint, good_rows bigint, bad_rows bigint, run_id string",
    ).withColumn("processed_at", F.current_timestamp()).writeTo(f"{CATALOG}.{args.silver_db}.etl_control").append()

    checked.unpersist()
    print(f"[{table}] snapshots ({start}, {end}]: events={events_read} good={good_rows} bad={bad_rows}")


def main():
    args = parse_args()
    tables = [t.strip() for t in args.tables.split(",") if t.strip()]
    unknown = [t for t in tables if t not in T.PRIMARY_KEYS]
    if unknown:
        raise ValueError(f"unknown tables: {unknown}")

    spark = SparkSession.builder.appName("bronze_to_silver").getOrCreate()
    run_id = str(uuid.uuid4())
    ensure_control_table(spark, args.silver_db)

    # one table failing must not hide the others; the job still fails at the end
    failed = []
    for table in tables:
        try:
            process_table(spark, args, table, run_id)
        except Exception as e:  # noqa: BLE001 - re-raised as job failure below
            print(f"[{table}] FAILED: {e}", file=sys.stderr)
            failed.append(table)

    spark.stop()
    if failed:
        raise SystemExit(f"tables failed: {failed}")


if __name__ == "__main__":
    main()
