
#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# AWS configuration
REGION="us-east-1"
ACCOUNT_ID="765332580934"
REPOSITORY="stock-bronze-catalog-manager"
IMAGE_TAG="v1"

ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY}"
LAMBDA_DIR="trans_layer/lambda_trans"

# Terraform modules
directories=(
    "vpc_config"
    "storage/s3_bronze"
    "ingestion/dms"
    "trans_layer/lambda_trans"
    "trans_layer/glue_data_catalog"
)

# ==========================================
# 1. Deploy Terraform infrastructure
# ==========================================

for dir in "${directories[@]}"; do

    echo "=================================="
    echo "Deploying $dir"
    echo "=================================="

    cd "$ROOT_DIR/$dir"

    terraform init
    terraform fmt
    terraform apply -auto-approve

done

cd "$ROOT_DIR"

echo "=================================="
echo "Infrastructure deployment completed"
echo "=================================="

# ==========================================
# 2. Prepare Docker public image pulls
# ==========================================

echo "Preparing temporary Docker configuration..."

mkdir -p /tmp/docker-public-config

echo '{"auths":{}}' > /tmp/docker-public-config/config.json

# ==========================================
# 3. Pull AWS Lambda base image
# ==========================================

echo "Pulling AWS Lambda Python base image..."

DOCKER_CONFIG=/tmp/docker-public-config \
docker pull public.ecr.aws/lambda/python:3.12

# ==========================================
# 4. Build Lambda container image
# ==========================================

echo "Building Lambda image..."

cd "$ROOT_DIR/$LAMBDA_DIR"

DOCKER_CONFIG=/tmp/docker-public-config \
docker build --platform linux/amd64 \
    -t "${REPOSITORY}:${IMAGE_TAG}" .

cd "$ROOT_DIR"

# ==========================================
# 5. Authenticate with AWS ECR
# ==========================================

echo "Authenticating with AWS ECR..."

aws ecr get-login-password --region "$REGION" | \
docker login \
    --username AWS \
    --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

# ==========================================
# 6. Tag and push Lambda image
# ==========================================

echo "Tagging Lambda image..."

docker tag "${REPOSITORY}:${IMAGE_TAG}" \
    "${ECR_URI}:${IMAGE_TAG}"

echo "Pushing Lambda image to ECR..."

docker push "${ECR_URI}:${IMAGE_TAG}"

echo "=================================="
echo "Infrastructure and image deployment completed!"
echo "=================================="
