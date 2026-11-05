
#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==========================================
# AWS configuration
# ==========================================

REGION="us-east-1"
IMAGE_TAG="v1"

LAMBDA_DIR="trans_layer/lambda_trans"

DOCKER_CONFIG_DIR="/tmp/docker-platform-config"

# Terraform modules deployed before Lambda
directories=(
    "vpc_config"
    "storage/s3_bronze"
    "trans_layer/glue_data_catalog"
    "ingestion/dms"
)

# ==========================================
# 1. Deploy prerequisite infrastructure
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

# ==========================================
# 2. Create ECR repository
# ==========================================

echo "=================================="
echo "Preparing ECR repository"
echo "=================================="

cd "$ROOT_DIR/$LAMBDA_DIR"

terraform init
terraform fmt

# Create only the ECR repository before pushing
terraform apply \
    -target=aws_ecr_repository.lambda \
    -auto-approve

ECR_URI="$(terraform output -raw ecr_repository_url)"

# ==========================================
# 3. Prepare Docker configuration
# ==========================================

echo "Preparing temporary Docker configuration..."

mkdir -p "$DOCKER_CONFIG_DIR"

echo '{"auths":{}}' > "$DOCKER_CONFIG_DIR/config.json"

# ==========================================
# 4. Build Lambda container image
# ==========================================

echo "=================================="
echo "Building Lambda image"
echo "=================================="

DOCKER_CONFIG="$DOCKER_CONFIG_DIR" \
docker build \
    --platform linux/amd64 \
    -t "${ECR_URI}:${IMAGE_TAG}" .

# ==========================================
# 5. Authenticate with AWS ECR
# ==========================================

echo "=================================="
echo "Authenticating with ECR"
echo "=================================="

aws ecr get-login-password --region "$REGION" | \
DOCKER_CONFIG="$DOCKER_CONFIG_DIR" docker login \
    --username AWS \
    --password-stdin "$ECR_URI"

# ==========================================
# 6. Push image to ECR
# ==========================================

echo "=================================="
echo "Pushing Lambda image"
echo "=================================="

DOCKER_CONFIG="$DOCKER_CONFIG_DIR" \
docker push "${ECR_URI}:${IMAGE_TAG}"

# ==========================================
# 7. Deploy Lambda infrastructure
# ==========================================

echo "=================================="
echo "Deploying Lambda infrastructure"
echo "=================================="

terraform apply -auto-approve

# ==========================================
# Completed
# ==========================================

cd "$ROOT_DIR"

echo "=================================="
echo "Platform deployment completed!"
echo "=================================="
