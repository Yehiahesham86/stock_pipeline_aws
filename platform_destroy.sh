#!/bin/bash

set -e

directories=(
    "ingestion/dms"
    "storage/s3_bronze"
    "vpc_config"
    "trans_layer/glue_data_catalog"
    "trans_layer/lambda_trans"
    
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