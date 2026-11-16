
import sys
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext

# --------------------------------------------------
# 1. Initialize Glue
# --------------------------------------------------

args = getResolvedOptions(
    sys.argv,
    ["JOB_NAME", "source_database", "target_database", "target_path"]
)

sc = SparkContext.getOrCreate()
glue_context = GlueContext(sc)
spark = glue_context.spark_session

job = Job(glue_context)
job.init(args["JOB_NAME"], args)

# --------------------------------------------------
# 2. Bronze source
# --------------------------------------------------

bronze_path = "s3://stock-bronze-unique123/bronze/"

bronze_df = (
    spark.read
    .option("recursiveFileLookup", "true")
    .parquet(bronze_path)
)

print("========== BRONZE SCHEMA ==========")
bronze_df.printSchema()

print("========== SAMPLE RECORDS ==========")
bronze_df.show(10, truncate=False)

print("========== COLUMN NAMES ==========")
print(bronze_df.columns)

# --------------------------------------------------
# 3. Record count
# --------------------------------------------------

print("Bronze record count:", bronze_df.count())

# --------------------------------------------------
# 4. Finish
# --------------------------------------------------

job.commit()
