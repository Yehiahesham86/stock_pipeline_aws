"""SQS (S3 .parquet created events) -> catalog_manager -> Athena INSERT INTO Bronze.

This is the Lambda SQS triggers. For every new Raw file:

  1. table = from the key  <RAW_PREFIX><SOURCE_SCHEMA>/<table>/...parquet
  2. call catalog_manager (synchronous) with {"table", "key"}
       -> creates / updates raw.<table> from the file's real schema
       -> returns the Raw columns
  3. Bronze schema sync:
       column in Raw, not in Bronze  -> ALTER TABLE bronze.<t> ADD COLUMNS
       same column, different type   -> fail (message retries, then DLQ)
  4. skip if Bronze already has rows with source_file = this file (idempotent)
  5. INSERT INTO bronze.<t> (<cols>, source_file, ingested_at)
     SELECT <cols>, '<s3 path>', current_timestamp
     FROM raw.<t> WHERE "$path" = '<s3 path>'
  6. re-count; 0 rows -> fail (no silent no-op)

Bronze is append-only: every change event (op I/U/D) is kept.
Latest-row-per-key + MERGE happens in Silver.

Also called once by Terraform with {"ddl": [...]} to create the Bronze
Iceberg tables (see create_tables). Raw tables are made by catalog_manager.

A failed message is reported in batchItemFailures, SQS retries it, and after
max_receive_count tries it goes to the DLQ.
"""

import json
import os
import time
import urllib.parse

import boto3

athena = boto3.client("athena")
glue = boto3.client("glue")
lambda_client = boto3.client("lambda")

# Bronze-only columns, filled by this Lambda (not in Raw)
ADDED_COLUMNS = ("source_file", "ingested_at")

# Raw type -> Bronze type where Iceberg differs (Iceberg has no tinyint/smallint)
BRONZE_TYPE = {"tinyint": "int", "smallint": "int"}

# stop waiting for Athena this many ms before the Lambda times out,
# so the failure is logged instead of a hard timeout
SAFETY_MS = 15000

WORKGROUP = os.environ["ATHENA_WORKGROUP"]
RAW_DATABASE = os.environ["RAW_DATABASE"]
BRONZE_DATABASE = os.environ["BRONZE_DATABASE"]
RAW_PREFIX = os.environ["RAW_PREFIX"]
SOURCE_SCHEMA = os.environ["SOURCE_SCHEMA"]
TABLES = [t.strip() for t in os.environ["TABLES"].split(",") if t.strip()]
CATALOG_MANAGER_FUNCTION = os.environ["CATALOG_MANAGER_FUNCTION"]


def log(**fields):
    # one JSON line per step -> easy to filter in CloudWatch Logs Insights
    print(json.dumps(fields, default=str))


# --------------------------------------------------
# Athena
# --------------------------------------------------

def run_query(sql, context=None):
    query_id = athena.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Database": BRONZE_DATABASE},
        WorkGroup=WORKGROUP,
    )["QueryExecutionId"]

    while True:
        status = athena.get_query_execution(QueryExecutionId=query_id)
        state = status["QueryExecution"]["Status"]["State"]

        if state == "SUCCEEDED":
            return query_id

        if state in ("FAILED", "CANCELLED"):
            reason = status["QueryExecution"]["Status"].get("StateChangeReason", "")
            raise RuntimeError(f"Athena query {query_id} {state}: {reason}")

        if context and context.get_remaining_time_in_millis() < SAFETY_MS:
            raise TimeoutError(f"Athena query {query_id} still {state}, Lambda almost out of time")

        time.sleep(2)


def query_count(sql, context):
    query_id = run_query(sql, context)
    rows = athena.get_query_results(QueryExecutionId=query_id)["ResultSet"]["Rows"]
    # row 0 = header, row 1 = the count
    return int(rows[1]["Data"][0]["VarCharValue"])


def sql_string(value):
    # escape ' for an SQL string literal
    return "'" + value.replace("'", "''") + "'"


# --------------------------------------------------
# Step 1: which table is this file?
# --------------------------------------------------

def table_from_key(key):
    prefix = f"{RAW_PREFIX}{SOURCE_SCHEMA}/"

    if not key.startswith(prefix):
        raise ValueError(f"Key {key!r} is not under {prefix!r}")

    table = key[len(prefix):].split("/", 1)[0]

    if table not in TABLES:
        raise ValueError(f"Table {table!r} from key {key!r} not in {TABLES}")

    return table


# --------------------------------------------------
# Step 2: catalog_manager updates the Raw table, returns its columns
# --------------------------------------------------

def update_raw_table(table, key):
    response = lambda_client.invoke(
        FunctionName=CATALOG_MANAGER_FUNCTION,
        InvocationType="RequestResponse",
        Payload=json.dumps({"table": table, "key": key}),
    )

    payload = json.loads(response["Payload"].read() or "null")

    # an exception inside catalog_manager still returns HTTP 200;
    # FunctionError is how you see it
    if response.get("FunctionError"):
        raise RuntimeError(f"catalog_manager failed for {key}: {payload}")

    log(step="raw_table", table=table, action=payload["action"])

    return {c["Name"]: c["Type"] for c in payload["columns"]}


# --------------------------------------------------
# Step 3: add new Raw columns to Bronze
# --------------------------------------------------

def bronze_columns(table):
    result = glue.get_table(DatabaseName=BRONZE_DATABASE, Name=table)
    columns = result["Table"]["StorageDescriptor"]["Columns"]
    return {c["Name"]: c["Type"] for c in columns if c["Name"] not in ADDED_COLUMNS}


def sync_bronze_schema(table, raw_cols, context):
    bronze_cols = bronze_columns(table)

    new_columns = []

    for name, raw_type in raw_cols.items():
        wanted = BRONZE_TYPE.get(raw_type, raw_type)

        if name not in bronze_cols:
            new_columns.append(f"`{name}` {wanted}")

        elif bronze_cols[name] != wanted:
            # type change in the source: don't guess, stop this file
            raise ValueError(
                f"{table}.{name}: Raw type {raw_type} vs Bronze {bronze_cols[name]}"
            )

    if new_columns:
        # Athena DDL uses backticks; Iceberg ADD COLUMNS is metadata only
        run_query(
            f"ALTER TABLE {BRONZE_DATABASE}.{table} ADD COLUMNS ({', '.join(new_columns)})",
            context,
        )
        log(step="bronze_schema", table=table, added=new_columns)
        bronze_cols = bronze_columns(table)

    return bronze_cols


# --------------------------------------------------
# Steps 4-6: load one file into Bronze
# --------------------------------------------------

def load_file(bucket, key, context):
    path = f"s3://{bucket}/{key}"
    table = table_from_key(key)

    raw_cols = update_raw_table(table, key)
    bronze_cols = sync_bronze_schema(table, raw_cols, context)

    bronze_table = f"{BRONZE_DATABASE}.{table}"
    raw_table = f"{RAW_DATABASE}.{table}"

    # SQS is at-least-once: the same file can arrive twice
    already = query_count(
        f"SELECT count(*) FROM {bronze_table} WHERE source_file = {sql_string(path)}",
        context,
    )
    if already > 0:
        log(step="skip", table=table, file=path, rows=already)
        return

    # only columns that exist in this file; a column dropped in the source
    # stays in Bronze and is NULL for new rows
    names = ", ".join(f'"{n}"' for n in bronze_cols if n in raw_cols)

    query_id = run_query(
        f"INSERT INTO {bronze_table} ({names}, source_file, ingested_at) "
        f"SELECT {names}, {sql_string(path)}, CAST(current_timestamp AS timestamp(6)) "
        f"FROM {raw_table} "
        f"WHERE \"$path\" = {sql_string(path)}",
        context,
    )

    inserted = query_count(
        f"SELECT count(*) FROM {bronze_table} WHERE source_file = {sql_string(path)}",
        context,
    )
    if inserted == 0:
        # e.g. Raw table location doesn't cover this file
        raise RuntimeError(f"INSERT {query_id} wrote 0 rows for {path}")

    log(step="loaded", table=table, file=path, rows=inserted, query=query_id)


def s3_objects(message_body):
    event = json.loads(message_body)

    # S3 sends one "s3:TestEvent" when the notification is created: no Records
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        # keys arrive URL-encoded (spaces = '+')
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        yield bucket, key


# --------------------------------------------------
# Bronze DDL on apply
# --------------------------------------------------

def create_tables(statements):
    # called by Terraform (aws_lambda_invocation) with {"ddl": [...]}
    # an exception here fails the terraform apply
    for sql in statements:
        query_id = run_query(sql)
        log(step="ddl", query=query_id)

    return {"created": len(statements)}


def lambda_handler(event, context):
    if "ddl" in event:
        return create_tables(event["ddl"])

    if "Records" not in event:
        raise ValueError(
            "Expected an SQS event (Records) or {'ddl': [...]}; "
            "to test by hand, copy a Raw object onto itself instead"
        )

    failures = []

    for message in event["Records"]:
        try:
            for bucket, key in s3_objects(message["body"]):
                load_file(bucket, key, context)
        except Exception as error:
            log(step="failed", message=message["messageId"], error=str(error))
            failures.append({"itemIdentifier": message["messageId"]})

    return {"batchItemFailures": failures}
