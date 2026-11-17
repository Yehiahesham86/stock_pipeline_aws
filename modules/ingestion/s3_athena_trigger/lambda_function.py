"""SQS (S3 .parquet created events) -> Athena INSERT INTO Bronze.

Also called once by Terraform with {"ddl": [...]} to create the Raw external
table and the Bronze Iceberg table (see create_tables).

One SQS message = one S3 event. For every new Raw file we run:

    INSERT INTO bronze.table (<bronze cols>, source_file, ingested_at)
    SELECT <bronze cols>, '<s3 path>', current_timestamp
    FROM raw.table
    WHERE "$path" = '<s3 path>'

<bronze cols> = Bronze columns read from Glue, picked from Raw by name.

The Lambda waits for the query. If it fails, that message is reported as
failed, SQS retries it, and after max_receive_count tries it goes to the DLQ.
"""

import json
import os
import time
import urllib.parse

import boto3

athena = boto3.client("athena")
glue = boto3.client("glue")

# Bronze-only columns, filled by this Lambda (not in Raw)
ADDED_COLUMNS = ("source_file", "ingested_at")

WORKGROUP = os.environ["ATHENA_WORKGROUP"]
RAW_DATABASE = os.environ["RAW_DATABASE"]
RAW_TABLE = os.environ["RAW_TABLE"]
BRONZE_DATABASE = os.environ["BRONZE_DATABASE"]
BRONZE_TABLE = os.environ["BRONZE_TABLE"]


def bronze_columns():
    # Bronze column names from Glue, minus the two this Lambda fills itself.
    # Selected BY NAME from Raw, so catalog_manager may re-order Raw columns.
    table = glue.get_table(DatabaseName=BRONZE_DATABASE, Name=BRONZE_TABLE)
    columns = table["Table"]["StorageDescriptor"]["Columns"]
    return [c["Name"] for c in columns if c["Name"] not in ADDED_COLUMNS]


def build_query(s3_path):
    # escape ' for the SQL string literal
    path = s3_path.replace("'", "''")
    names = ", ".join(f'"{name}"' for name in bronze_columns())
    return (
        f"INSERT INTO {BRONZE_DATABASE}.{BRONZE_TABLE} "
        f"({names}, source_file, ingested_at) "
        f"SELECT {names}, '{path}', CAST(current_timestamp AS timestamp(6)) "
        f"FROM {RAW_DATABASE}.{RAW_TABLE} "
        f"WHERE \"$path\" = '{path}'"
    )


def run_query(sql):
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

        time.sleep(2)


def s3_paths(message_body):
    event = json.loads(message_body)

    # S3 sends one "s3:TestEvent" when the notification is created: no Records
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        # keys arrive URL-encoded (spaces = '+')
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        yield f"s3://{bucket}/{key}"


def create_tables(statements):
    # called by Terraform (aws_lambda_invocation) with {"ddl": [...]}
    # an exception here fails the terraform apply
    for sql in statements:
        query_id = run_query(sql)
        print(f"DDL OK query={query_id}")

    return {"created": len(statements)}


def lambda_handler(event, context):
    if "ddl" in event:
        return create_tables(event["ddl"])

    failures = []

    for message in event["Records"]:
        try:
            for path in s3_paths(message["body"]):
                query_id = run_query(build_query(path))
                print(f"OK {path} query={query_id}")
        except Exception as error:
            print(f"FAILED message={message['messageId']}: {error}")
            failures.append({"itemIdentifier": message["messageId"]})

    return {"batchItemFailures": failures}
