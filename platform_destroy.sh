
#!/bin/bash

set -e

# Resolve project root regardless of where the script is launched
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Destroy in reverse dependency order
directories=(
    "trans_layer/glue_etl"
    "trans_layer/lambda_trans"
    "trans_layer/glue_data_catalog"
    "ingestion/dms"
    "storage/s3_bronze"
    "vpc_config"
)

echo "=========================================="
echo " Destroying Stock Data Pipeline"
echo "=========================================="

for dir in "${directories[@]}"; do

    TARGET_DIR="$ROOT_DIR/$dir"

    echo ""
    echo "=========================================="
    echo " Destroying: $dir"
    echo "=========================================="

    if [ ! -d "$TARGET_DIR" ]; then
        echo "Directory not found. Skipping..."
        continue
    fi

    if ! compgen -G "$TARGET_DIR/*.tf" > /dev/null; then
        echo "No Terraform configuration found. Skipping..."
        continue
    fi

    cd "$TARGET_DIR"

    echo "Initializing Terraform..."
    terraform init -input=false

    echo "Destroying infrastructure..."
    terraform destroy -auto-approve -input=false

    echo "Successfully destroyed: $dir"

done

echo ""
echo "=========================================="
echo " All Terraform modules processed!"
echo "=========================================="
