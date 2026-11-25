# dbt for the Silver -> Gold step, run as an ECS Fargate task.
#
#   Python 3.11 + dbt-core + dbt-athena (versions pinned in requirements.txt)
#   + this dbt project
#
# dbt only sends SQL to Athena; credentials = ECS task role (boto3 default chain).
# Built + pushed by Terraform (../ecr.tf), rebuilt when any project file changes.

FROM python:3.11.10-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DBT_PROFILES_DIR=/app

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# don't run as root; dbt writes target/ and logs/ next to the project
RUN useradd --create-home --uid 1000 dbt
WORKDIR /app
COPY --chown=dbt:dbt . .
RUN chown dbt:dbt /app
USER dbt

# command (build --target aws) comes from the ECS task definition
ENTRYPOINT ["dbt"]
