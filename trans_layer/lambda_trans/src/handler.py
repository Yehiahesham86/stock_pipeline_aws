
import os
import json
import logging

import boto3
import pyarrow as pa
import pyarrow.parquet as pq
from pyarrow import fs

logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

s3 = boto3.client("s3", region_name=AWS_REGION)
glue = boto3.client("glue", region_name=AWS_REGION)

bronze_bucket_name = os.environ["bronze_bucket_name"]
DATABASE_NAME = os.environ["DATABASE_NAME"]
TABLE_NAME = os.environ.get("TABLE_NAME", "stock_prices")

S3_PREFIX = os.environ.get(
    "S3_PREFIX",
    "bronze/public/stock_prices/"
)


def get_parquet_file():
    """Find the first Parquet file using S3 pagination."""

    paginator = s3.get_paginator("list_objects_v2")

    for page in paginator.paginate(
        Bucket=bronze_bucket_name,
        Prefix=S3_PREFIX
    ):
        for obj in page.get("Contents", []):
            key = obj["Key"]

            if key.lower().endswith(".parquet"):
                return key

    return None


def discover_schema(key):
    """Read the schema from a Parquet file in S3."""

    s3_filesystem = fs.S3FileSystem(region=AWS_REGION)

    parquet_path = f"{bronze_bucket_name}/{key}"

    parquet_file = pq.ParquetFile(
        parquet_path,
        filesystem=s3_filesystem
    )

    return parquet_file.schema_arrow


def convert_type(arrow_type):
    """Convert PyArrow data types into Glue-compatible types."""

    if pa.types.is_string(arrow_type) or pa.types.is_large_string(arrow_type):
        return "string"

    if pa.types.is_boolean(arrow_type):
        return "boolean"

    if pa.types.is_integer(arrow_type):
        return "int" if pa.types.is_int32(arrow_type) else "bigint"

    if pa.types.is_floating(arrow_type):
        return "float" if pa.types.is_float32(arrow_type) else "double"

    if pa.types.is_decimal(arrow_type):
        return f"decimal({arrow_type.precision},{arrow_type.scale})"

    if pa.types.is_date(arrow_type):
        return "date"

    if pa.types.is_timestamp(arrow_type):
        return "timestamp"

    if pa.types.is_binary(arrow_type) or pa.types.is_large_binary(arrow_type):
        return "binary"

    logger.warning("Unrecognized Arrow type %s; using string", arrow_type)

    return "string"


def build_columns(schema):
    """Build Glue column definitions."""

    columns = []

    for field in schema:
        columns.append({
            "Name": field.name,
            "Type": convert_type(field.type)
        })

    return columns


def create_or_update_table(columns):
    """Create or update the Glue Catalog table."""

    table_input = {
        "Name": TABLE_NAME,
        "TableType": "EXTERNAL_TABLE",
        "Parameters": {
            "classification": "parquet",
            "EXTERNAL": "TRUE"
        },
        "StorageDescriptor": {
            "Columns": columns,
            "Location": f"s3://{bronze_bucket_name}/{S3_PREFIX}",
            "InputFormat": (
                "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
            ),
            "OutputFormat": (
                "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
            ),
            "SerdeInfo": {
                "SerializationLibrary": (
                    "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
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
            Name=TABLE_NAME
        )

        glue.update_table(
            DatabaseName=DATABASE_NAME,
            TableInput=table_input
        )

        logger.info("Updated Glue table: %s", TABLE_NAME)

    except glue.exceptions.EntityNotFoundException:

        glue.create_table(
            DatabaseName=DATABASE_NAME,
            TableInput=table_input
        )

        logger.info("Created Glue table: %s", TABLE_NAME)


def lambda_handler(event, context):

    logger.info("Starting Bronze catalog registration")

    key = get_parquet_file()

    if not key:
        logger.info("No Parquet files found in S3.")

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "No Parquet files found. Nothing to catalog yet."
            })
        }

    logger.info("Selected Parquet file: %s", key)

    schema = discover_schema(key)

    logger.info("Discovered schema: %s", schema)

    columns = build_columns(schema)

    create_or_update_table(columns)

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Glue table registered successfully",
            "database": DATABASE_NAME,
            "table": TABLE_NAME,
            "source_file": key,
            "columns": columns
        })
    }
