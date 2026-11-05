#!/bin/bash

set -e

directories=(
    "trans_layer/lambda_trans"
    "ingestion/dms"
    "trans_layer/glue_data_catalog"
    "storage/s3_bronze"
    "vpc_config"
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