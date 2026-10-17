#!/usr/bin/env bash
# Step 4: Delete everything the lab created. EKS costs money every hour — don't skip this!
set -uo pipefail
source "$(dirname "$0")/config.sh"

echo ">> Deleting the website namespace (this also deletes the AWS load balancer)..."
kubectl delete namespace website --ignore-not-found --wait=true

echo ">> Deleting EKS cluster '${CLUSTER_NAME}' (~10 minutes)..."
eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --wait

echo ">> Deleting ECR repository '${ECR_REPO}' and its images..."
aws ecr delete-repository --repository-name "$ECR_REPO" --force --region "$AWS_REGION" >/dev/null 2>&1

echo "✅ Cleanup complete."
