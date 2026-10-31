#!/bin/bash

set -e

directories=(
    "storage/s3_bronze"
    "vpc_config"
    "ingestion/dms"
)

for dir in "${directories[@]}"; do
    echo "=================================="
    echo "Deploying $dir"
    echo "=================================="

    cd "$dir"

    terraform init
    terraform apply -auto-approve

    cd - > /dev/null
done

echo "All infrastructure deployed successfully!"