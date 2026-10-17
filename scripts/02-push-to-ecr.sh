#!/usr/bin/env bash
# Step 2: Build the website image and push it to Amazon ECR.
set -euo pipefail
source "$(dirname "$0")/config.sh"

echo ">> Creating ECR repository '${ECR_REPO}' (if missing)..."
aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || \
  aws ecr create-repository \
    --repository-name "$ECR_REPO" \
    --image-scanning-configuration scanOnPush=true \
    --region "$AWS_REGION" >/dev/null

echo ">> Logging Docker in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo ">> Building image (linux/amd64 to match t3 nodes)..."
docker build --platform linux/amd64 -t "${ECR_URI}:${IMAGE_TAG}" "$(dirname "$0")/../app"

echo ">> Pushing ${ECR_URI}:${IMAGE_TAG}..."
docker push "${ECR_URI}:${IMAGE_TAG}"
