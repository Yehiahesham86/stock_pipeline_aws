#!/bin/bash

set -e

directories=(
    "vpc_config"
    "storage/s3_bronze"
    "ingestion/dms"
)

for dir in "${directories[@]}"; do
    echo "=================================="
    echo "Deploying $dir"
    echo "=================================="

    cd "$dir"

    terraform init
    terraform destroy -auto-approve

    cd - > /dev/null
done

echo "All infrastructure destroyed successfully!"