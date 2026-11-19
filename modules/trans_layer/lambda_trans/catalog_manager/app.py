"""catalog_manager: owns the Raw Glue tables (instead of a Glue Crawler).

Reads the schema of a real DMS parquet file (footer only) and creates or
updates <raw_db>.<table> in the Glue Data Catalog.

Two ways to call it:

1. From the trigger Lambda, once per new Raw file (synchronous):
       {"table": "students", "key": "raw/app/students/2026/11/19/x.parquet"}
   -> schema of THAT file (it is the newest one)
   -> returns {"table", "action", "source_file", "columns"}

2. By hand / backfill, empty event {}:
   -> for every table: schema of the NEWEST parquet file (by LastModified)
   -> returns {"results": [...]}

Idempotent: if the Glue columns already match the file, nothing is written.
"""

import os
import json
import logging

import boto3
import pyarrow as pa
import pyarrow.parquet as pq
from pyarrow import fs

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# --------------------------------------------------
# CONFIGURATION (all set by Terraform, no defaults on purpose:
# a missing variable fails at cold start instead of using a wrong value)
# --------------------------------------------------

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

RAW_BUCKET_NAME = os.environ["RAW_BUCKET_NAME"]
DATABASE_NAME = os.environ["DATABASE_NAME"]
RAW_PREFIX = os.environ["RAW_PREFIX"]          # e.g. raw/
SOURCE_SCHEMA = os.environ["SOURCE_SCHEMA"]    # e.g. app
TABLES = [t.strip() for t in os.environ["TABLES"].split(",") if t.strip()]

s3 = boto3.client("s3", region_name=AWS_REGION)
glue = boto3.client("glue", region_name=AWS_REGION)

s3_filesystem = fs.S3FileSystem(region=AWS_REGION)


def table_prefix(table):
    return f"{RAW_PREFIX}{SOURCE_SCHEMA}/{table}/"


# --------------------------------------------------
# FIND THE NEWEST PARQUET FILE
# --------------------------------------------------

def get_latest_parquet_file(table):
    """
    Newest Parquet file of a table, by LastModified.

    NOT the last key in the listing: S3 lists keys alphabetically, and
    'LOAD00000001.parquet' sorts after '2026/11/19/...parquet' ('L' > '2'),
    so the last key would be the old full-load file.
    """

    paginator = s3.get_paginator("list_objects_v2")

    latest = None

    for page in paginator.paginate(
        Bucket=RAW_BUCKET_NAME,
        Prefix=table_prefix(table)
    ):

        for obj in page.get("Contents", []):

            if not obj["Key"].lower().endswith(".parquet"):
                continue

            if latest is None or obj["LastModified"] > latest["LastModified"]:
                latest = obj

    if latest is None:
        logger.warning("No Parquet files found for table: %s", table)
        return None

    logger.info("Newest Parquet file for %s: %s", table, latest["Key"])

    return latest["Key"]


# --------------------------------------------------
# DISCOVER PARQUET SCHEMA
# --------------------------------------------------

def discover_schema(key):
    """
    Read the schema from an actual Parquet file in S3 (footer only,
    not the data).
    """

    parquet_path = f"{RAW_BUCKET_NAME}/{key}"

    parquet_file = pq.ParquetFile(
        parquet_path,
        filesystem=s3_filesystem
    )

    return parquet_file.schema_arrow


# --------------------------------------------------
# CONVERT PYARROW TYPES TO GLUE TYPES
# --------------------------------------------------

def convert_type(arrow_type):

    if pa.types.is_string(arrow_type) or pa.types.is_large_string(arrow_type):
        return "string"

    if pa.types.is_boolean(arrow_type):
        return "boolean"

    if pa.types.is_int8(arrow_type):
        return "tinyint"

    if pa.types.is_int16(arrow_type):
        return "smallint"

    if pa.types.is_int32(arrow_type):
        return "int"

    if pa.types.is_int64(arrow_type):
        return "bigint"

    if pa.types.is_floating(arrow_type):
        return "float" if pa.types.is_float32(arrow_type) else "double"

    if pa.types.is_decimal(arrow_type):
        return (
            f"decimal({arrow_type.precision},"
            f"{arrow_type.scale})"
        )

    if pa.types.is_date(arrow_type):
        return "date"

    if pa.types.is_timestamp(arrow_type):
        return "timestamp"

    if pa.types.is_binary(arrow_type) or pa.types.is_large_binary(arrow_type):
        return "binary"

    raise ValueError(
        f"Unsupported PyArrow data type: {arrow_type}"
    )


def build_columns(schema):

    columns = []

    for field in schema:

        columns.append({
            # lowercase: DMS writes "Op", Glue/Athena names are lowercase,
            # and the trigger compares Raw vs Bronze columns by name
            "Name": field.name.lower(),
            "Type": convert_type(field.type)
        })

    return columns


# --------------------------------------------------
# CREATE OR UPDATE GLUE TABLE
# --------------------------------------------------

def create_or_update_table(table, columns):

    table_location = f"s3://{RAW_BUCKET_NAME}/{table_prefix(table)}"

    table_input = {

        "Name": table,

        "TableType": "EXTERNAL_TABLE",

        "Parameters": {
            "classification": "parquet",
            "EXTERNAL": "TRUE"
        },

        "StorageDescriptor": {

            "Columns": columns,

            "Location": table_location,

            "InputFormat": (
                "org.apache.hadoop.hive.ql.io.parquet."
                "MapredParquetInputFormat"
            ),

            "OutputFormat": (
                "org.apache.hadoop.hive.ql.io.parquet."
                "MapredParquetOutputFormat"
            ),

            "SerdeInfo": {

                "SerializationLibrary": (
                    "org.apache.hadoop.hive.ql.io.parquet.serde."
                    "ParquetHiveSerDe"
                ),

                "Parameters": {
                    "serialization.format": "1"
                }
            }
        }
    }

    try:

        existing = glue.get_table(
            DatabaseName=DATABASE_NAME,
            Name=table
        )

        existing_columns = [
            {"Name": c["Name"], "Type": c["Type"]}
            for c in existing["Table"]["StorageDescriptor"]["Columns"]
        ]

        # called once per file: don't write a new Glue table version
        # when nothing changed
        if existing_columns == columns:

            logger.info("Glue table unchanged: %s", table)

            return "unchanged"

        glue.update_table(
            DatabaseName=DATABASE_NAME,
            TableInput=table_input
        )

        logger.info(
            "Updated Glue table %s: %s -> %s",
            table,
            existing_columns,
            columns
        )

        action = "updated"

    except glue.exceptions.EntityNotFoundException:

        glue.create_table(
            DatabaseName=DATABASE_NAME,
            TableInput=table_input
        )

        logger.info("Created Glue table: %s", table)

        action = "created"

    return action


# --------------------------------------------------
# REGISTER ONE TABLE FROM ONE FILE
# --------------------------------------------------

def register_table(table, key):

    if table not in TABLES:
        raise ValueError(f"Unknown table {table!r}, expected one of {TABLES}")

    if not key.startswith(table_prefix(table)):
        raise ValueError(f"Key {key!r} is not under {table_prefix(table)!r}")

    schema = discover_schema(key)

    logger.info("Discovered schema for %s: %s", table, schema)

    columns = build_columns(schema)

    action = create_or_update_table(table, columns)

    return {
        "table": table,
        "action": action,
        "source_file": key,
        "columns": columns
    }


# --------------------------------------------------
# REGISTER ALL RAW TABLES (manual / backfill)
# --------------------------------------------------

def register_all_tables():

    results = []

    for table in TABLES:

        logger.info("Processing table: %s", table)

        key = get_latest_parquet_file(table)

        if not key:

            results.append({
                "table": table,
                "action": "skipped",
                "reason": "No Parquet files found"
            })

            continue

        results.append(register_table(table, key))

    return results


# --------------------------------------------------
# LAMBDA HANDLER
# --------------------------------------------------

def lambda_handler(event, context):

    logger.info("Event: %s", json.dumps(event, default=str))

    # 1. called by the trigger Lambda for one new file
    if event.get("table") and event.get("key"):
        return register_table(event["table"], event["key"])

    # 2. manual run: newest file of every table
    results = register_all_tables()

    logger.info("Registration results: %s", results)

    return {"database": DATABASE_NAME, "results": results}
