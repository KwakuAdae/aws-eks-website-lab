#!/usr/bin/env bash
# Shared lab settings. Override any value by exporting it before running a script.
export AWS_REGION="${AWS_REGION:-us-east-1}"
export CLUSTER_NAME="${CLUSTER_NAME:-eks-website-lab}"
export ECR_REPO="${ECR_REPO:-eks-website}"
export IMAGE_TAG="${IMAGE_TAG:-v1}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
export ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"
