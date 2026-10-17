#!/usr/bin/env bash
# Step 1: Create the EKS cluster and managed node group (takes ~15-20 minutes).
set -euo pipefail
source "$(dirname "$0")/config.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo ">> Cluster '${CLUSTER_NAME}' already exists, skipping creation."
else
  echo ">> Creating EKS cluster '${CLUSTER_NAME}' in ${AWS_REGION} (grab a coffee ☕)..."
  sed -e "s/^  name: eks-website-lab/  name: ${CLUSTER_NAME}/" \
      -e "s/^  region: us-east-1/  region: ${AWS_REGION}/" \
      "${ROOT}/eks/cluster.yaml" | eksctl create cluster -f -
fi

echo ">> Updating kubeconfig..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

echo ">> Nodes:"
kubectl get nodes -o wide
