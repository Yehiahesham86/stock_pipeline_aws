# Spark (local mode, one container) for the Bronze -> Silver job on ECS Fargate.
#
#   Python 3.11 + Java 17 + PySpark 3.5.4 (same Spark line as Glue 5 / EMR 7)
#   + Iceberg 1.6.1 runtime + Iceberg AWS bundle (GlueCatalog, S3FileIO)
#   + hadoop-aws 3.3.4 (= PySpark's Hadoop) for plain s3:// writes (quarantine parquet)
#
# All versions pinned. Built + pushed by Terraform (ecr.tf), rebuilt when any
# file in jobs/ changes.

FROM python:3.11.10-slim-bookworm

ARG PYSPARK_VERSION=3.5.4
ARG ICEBERG_VERSION=1.6.1
ARG HADOOP_AWS_VERSION=3.3.4
ARG AWS_SDK_BUNDLE_VERSION=1.12.262

RUN apt-get update \
    && apt-get install -y --no-install-recommends openjdk-17-jre-headless curl ca-certificates procps \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

RUN pip install --no-cache-dir pyspark==${PYSPARK_VERSION}

# extra jars go straight into PySpark's jars/ -> on the classpath without --jars
RUN JARS="$(python -c 'import os, pyspark; print(os.path.join(os.path.dirname(pyspark.__file__), "jars"))')" \
    && M=https://repo1.maven.org/maven2 \
    && curl -fsSL -o "$JARS/iceberg-spark-runtime-3.5_2.12-${ICEBERG_VERSION}.jar" \
         "$M/org/apache/iceberg/iceberg-spark-runtime-3.5_2.12/${ICEBERG_VERSION}/iceberg-spark-runtime-3.5_2.12-${ICEBERG_VERSION}.jar" \
    && curl -fsSL -o "$JARS/iceberg-aws-bundle-${ICEBERG_VERSION}.jar" \
         "$M/org/apache/iceberg/iceberg-aws-bundle/${ICEBERG_VERSION}/iceberg-aws-bundle-${ICEBERG_VERSION}.jar" \
    && curl -fsSL -o "$JARS/hadoop-aws-${HADOOP_AWS_VERSION}.jar" \
         "$M/org/apache/hadoop/hadoop-aws/${HADOOP_AWS_VERSION}/hadoop-aws-${HADOOP_AWS_VERSION}.jar" \
    && curl -fsSL -o "$JARS/aws-java-sdk-bundle-${AWS_SDK_BUNDLE_VERSION}.jar" \
         "$M/com/amazonaws/aws-java-sdk-bundle/${AWS_SDK_BUNDLE_VERSION}/aws-java-sdk-bundle-${AWS_SDK_BUNDLE_VERSION}.jar"

# don't run as root
RUN useradd --create-home --uid 1000 spark
WORKDIR /app
COPY transforms.py bronze_to_silver.py ./
USER spark

# command (spark-submit + conf + job args) comes from the ECS task definition
ENTRYPOINT ["spark-submit"]
