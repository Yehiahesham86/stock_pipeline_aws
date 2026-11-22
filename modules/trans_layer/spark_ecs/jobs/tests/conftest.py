import os
import sys

import pytest
from pyspark.sql import SparkSession

# make `import transforms` work from jobs/
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Spark workers must use the same interpreter as pytest (on Windows the default
# "python" lookup can hit the Store stub and the worker never connects back)
os.environ.setdefault("PYSPARK_PYTHON", sys.executable)
os.environ.setdefault("PYSPARK_DRIVER_PYTHON", sys.executable)


@pytest.fixture(scope="session")
def spark(tmp_path_factory):
    builder = (
        SparkSession.builder.master("local[1]")
        .appName("transforms-tests")
        .config("spark.sql.shuffle.partitions", "1")
        .config("spark.sql.session.timeZone", "UTC")
        .config("spark.ui.enabled", "false")
    )
    # Optional: Iceberg MERGE tests run only when ICEBERG_JAR points at
    # iceberg-spark-runtime-3.5_2.12-<ver>.jar (in the Glue 5 image:
    # /usr/share/aws/iceberg/lib/iceberg-spark3-runtime.jar)
    jar = os.environ.get("ICEBERG_JAR")
    if jar:
        builder = (
            builder.config("spark.jars", jar)
            .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
            .config("spark.sql.catalog.local", "org.apache.iceberg.spark.SparkCatalog")
            .config("spark.sql.catalog.local.type", "hadoop")
            .config("spark.sql.catalog.local.warehouse", str(tmp_path_factory.mktemp("warehouse")))
        )
    session = builder.getOrCreate()
    yield session
    session.stop()
