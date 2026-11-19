
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
# CONFIGURATION
# --------------------------------------------------

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

RAW_BUCKET_NAME = os.environ["RAW_BUCKET_NAME"]
DATABASE_NAME = os.environ.get("DATABASE_NAME", "stock_raw")

SOURCE_SCHEMA = os.environ.get("SOURCE_SCHEMA", "app")
RAW_PREFIX = os.environ.get("RAW_PREFIX", "raw/")

TABLES = [
    "teachers",
    "students",
    "class_bookings",
    "payments",
    "referrals"
]

s3 = boto3.client("s3", region_name=AWS_REGION)
glue = boto3.client("glue", region_name=AWS_REGION)

s3_filesystem = fs.S3FileSystem(region=AWS_REGION)


# --------------------------------------------------
# FIND PARQUET FILE
# --------------------------------------------------

def get_parquet_file(table):
    """
    Find the first Parquet file belonging to a table.
    """

    prefix = f"{RAW_PREFIX}{SOURCE_SCHEMA}/{table}/"

    paginator = s3.get_paginator("list_objects_v2")

    for page in paginator.paginate(
        Bucket=RAW_BUCKET_NAME,
        Prefix=prefix
    ):

        for obj in page.get("Contents", []):

            key = obj["Key"]

            if key.lower().endswith(".parquet"):

                logger.info(
                    "Found Parquet file for %s: %s",
                    table,
                    key
                )

                return key

    logger.warning("No Parquet files found for table: %s", table)

    return None


# --------------------------------------------------
# DISCOVER PARQUET SCHEMA
# --------------------------------------------------

def discover_schema(key):
    """
    Read the schema from an actual Parquet file in S3.
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
            "Name": field.name,
            "Type": convert_type(field.type)
        })

    return columns


# --------------------------------------------------
# CREATE OR UPDATE GLUE TABLE
# --------------------------------------------------

def create_or_update_table(table, columns):

    table_location = (
        f"s3://{RAW_BUCKET_NAME}/"
        f"{RAW_PREFIX}{SOURCE_SCHEMA}/{table}/"
    )

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

        glue.get_table(
            DatabaseName=DATABASE_NAME,
            Name=table
        )

        glue.update_table(
            DatabaseName=DATABASE_NAME,
            TableInput=table_input
        )

        logger.info("Updated Glue table: %s", table)

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
# REGISTER ALL RAW TABLES
# --------------------------------------------------

def register_all_tables():

    results = []

    for table in TABLES:

        logger.info("Processing table: %s", table)

        key = get_parquet_file(table)

        if not key:

            results.append({
                "table": table,
                "status": "skipped",
                "reason": "No Parquet files found"
            })

            continue

        schema = discover_schema(key)

        logger.info(
            "Discovered schema for %s: %s",
            table,
            schema
        )

        columns = build_columns(schema)

        action = create_or_update_table(
            table,
            columns
        )

        results.append({

            "table": table,

            "status": action,

            "source_file": key,

            "columns": columns
        })

    return results


# --------------------------------------------------
# LAMBDA HANDLER
# --------------------------------------------------

def lambda_handler(event, context):

    logger.info("Starting Raw Glue Catalog registration")

    logger.info("Region: %s", AWS_REGION)
    logger.info("Raw bucket: %s", RAW_BUCKET_NAME)
    logger.info("Glue database: %s", DATABASE_NAME)

    results = register_all_tables()

    successful = [
        item for item in results
        if item["status"] in ["created", "updated"]
    ]

    skipped = [
        item for item in results
        if item["status"] == "skipped"
    ]

    logger.info("Registration results: %s", results)

    return {

        "statusCode": 200,

        "body": json.dumps({

            "message": "Raw Glue registration completed",

            "database": DATABASE_NAME,

            "registered_tables": len(successful),

            "skipped_tables": len(skipped),

            "results": results

        }, default=str)
    }
