#!/bin/bash

set -e

directories=(
    "storage/s3_bronze"
    "vpc_config"
    "ingestion/dms"
    "trans_layer/glue_data_catalog"
    "trans_layer/crawler"
)

for dir in "${directories[@]}"; do
    echo "=================================="
    echo "Deploying $dir"
    echo "=================================="

    cd "$dir"

    terraform init
    terraform fmt
    terraform apply -auto-approve

    cd - > /dev/null
done

echo "All infrastructure deployed successfully!"